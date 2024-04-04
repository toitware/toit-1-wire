// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import crypto.crc
import gpio
import system show BITS-PER-BYTE
import rmt

/**
Support for 1-wire protocol.

The 1-wire protocol is implemented with ESP32's hardware supported RMT module.
*/

/**
A 1-wire bus.
*/
class Bus:
  static COMMAND-ROM-MATCH_  ::= 0x55
  static COMMAND-ROM-SKIP_   ::= 0xCC
  static COMMAND-ROM-SEARCH_ ::= 0xF0
  static COMMAND-ROM-READ_   ::= 0x33
  static COMMAND-ROM-SEARCH-ALARM_ ::= 0xEC

  /**
  Marker to indicate that all devices of the given family should be skipped
    during the search.

  A block should return this value when no other device of the family should
    be given to the block.
  */
  static SKIP-FAMILY ::= Object

  /**
  The protocol.
  Use the $protocol_ accessor to use the protocol.
  */
  protocol__/Protocol? := ?

  protocol_ --power/bool -> Protocol:
    if not protocol__: throw "BUS CLOSED"
    protocol__.set-power power
    return protocol__

  /**
  Constructs a 1-wire bus using the given $protocol.
  */
  constructor.protocol protocol/Protocol:
    protocol__ = protocol

  /**
  Constructs a 1-wire bus for the given $pin.

  If $pull-up is set, then the pin's pull-up resistor is enabled. The
    ESP32's internal pull-up has significantly higher resistance (~50kΩ) than
    the 4.7kΩ pull-up resistor that the 1-wire protocol requires.
    However, in many cases the internal pull-up still works fine and is
    sufficient.

  This constructor uses the default parameters for the protocol. Use
    $Bus.protocol if you need to customize the protocol.
  */
  constructor pin/gpio.Pin --pull-up/bool=false:
    protocol__ = Protocol pin --pull-up=pull-up

  /** Whether this bus is closed. */
  is-closed -> bool:
    return protocol__ == null

  /**
  Closes this bus and releases the underlying resources.
  */
  close:
    if protocol__:
      protocol__.close
      protocol__ = null

  /**
  Selects the device with the given $device-id.

  The $device-id is a byte array of length 8.
  */
  select device-id/int -> none:
    if not reset: throw "NO DEVICE"
    write-byte COMMAND-ROM-MATCH_
    write-bits device-id --count=64

  /**
  Skips the device selection step.

  This is useful when there is only one device on the bus, or
    if multiple devices are addressed at the same time.
  */
  skip -> none:
    if not reset: throw "NO DEVICE"
    write-byte COMMAND-ROM-SKIP_

  /**
  Reads the device id of the single device on the bus.

  If multiple devices are on the bus, then the result is
    the bit-and of all device ids, and thus unusable.
  */
  read-device-id -> int:
    if not reset: throw "NO DEVICE"
    write-byte COMMAND-ROM-READ_
    return read-bits 64

  /**
  Writes a single bit $value on the bus.
  If $activate-power is true, disables the pin's open-drain so that
    the pin can be used as a power source. An ESP32 can source up to 12 mA
    in this configuration.
  The pin is automatically set back to open-drain mode the next time
    any operation is performed.
  */
  write-bit value/int --activate-power/bool=false -> none:
    (protocol_ --power=activate-power).write-bits value 1

  /**
  Variant of $write-bit.

  Writes $count bits from $value on the bus.
  */
  write-bits value/int --count/int --activate-power/bool=false -> none:
    (protocol_ --power=activate-power).write-bits value count

  /**
  Variant of $write-bit.

  Writes a single byte $value to the pin.
  */
  write-byte value/int --activate-power/bool=false -> none:
    (protocol_ --power=activate-power).write-byte value

  /**
  Variant of $write-bit.

  Writes all given $bytes to the pin.
  The $bytes are written individually, and not as a single bit sequence.
  */
  write bytes/ByteArray --activate-power/bool=false -> none:
    (protocol_ --power=activate-power).write bytes

  /**
  Reads a single bit from the pin.
  */
  read-bit -> int:
    return (protocol_ --no-power).read-bits 1

  /**
  Reads $count bits from the pin.

  The parameter $count must satisfy 0 <= $count <= 8. That is,
    at most one byte can be read at a time.
  */
  read-bits count/int -> int:
    return (protocol_ --no-power).read-bits count

  /**
  Reads a single byte from the pin.
  */
  read-byte -> int:
    return (protocol_ --no-power).read-byte

  /**
  Reads $count bytes from the pin.

  The reading operation assumes that the bytes are sent individually.
  */
  read count/int -> ByteArray:
    return (protocol_ --no-power).read count

  /**
  Sends a reset and returns whether any device is present.
  */
  reset -> bool:
    return (protocol_ --no-power).reset

  /**
  Searches for devices on the bus and calls the $block with
    the device id of each found device.

  If $alarm-only is set, then searches for devices that have
    triggered an alarm.

  If a $family is given, then only devices with that family
    are searched for.
  */
  do --alarm-only/bool=false --family/int?=null [block] -> none:
    if family:
      // Start the search with the family id.
      // By setting the previous_last_unexplored_branch to 64 (any higher value
      // would work too), we are letting
      // the search always take the '0' branch for the non-family bits.
      // Note that the search overwrites the id for non-collision bits.
      // As a consequence, the search will find the first device with an
      // id that is greater or equal to the family id.
      search_
          --alarm-only=alarm-only
          --start-id=family
          --fixed-bits=8
          : | id |
            if id & 0xFF != family: return
            block.call id
    else:
      search_ --alarm-only=alarm-only block

  /**
  Searches for the device with the given id.

  Returns true if the device responded.
  */
  ping id/int -> bool:
    search_ --no-alarm-only --start-id=id --fixed-bits=64: | found-id |
      return found-id == id
    return false

  search_ --alarm-only/bool --start-id/int=0 --fixed-bits/int=-1 [block]-> none:
    // Search algorithm is explained here:
    //   https://www.analog.com/en/app-notes/1wire-search-algorithm.html

    // Summary:
    // The controller starts by sending out a 'search' command.
    // The devices respond with the least-significant bit of their ID and
    // the complement of that bit. This allows the controller to detect collisions,
    // since both bits are 0 in that case (open-drain).
    // The controller than chooses the path to take by emitting the next bit.
    // If there was no collision, that's the one it received. Otherwise it chooses
    // one of the two possibilities. At the same time, it remembers the bit-position
    // at which it had to make a choice.
    // Once a full id has been constructed, the controller resets the bus and
    // tries again. It uses the constructed id for all the bits until the last
    // decision point, and then takes the other path. In the process, it also
    // updates the last decision point, so it can continue from there the next time.
    // This process is repeated until all devices have been found.

    // The 'id' variable accumulates the bits of the branches we take.
    // The bits in the range [0..last_branch] are also used to remember
    // the path that was taken until the 'last_branch' bit.
    // Note that the currently unused id bits may not be '0', due to back tracking.
    id := start-id

    // Keeps track of the last bit position where we branched and still have to
    // take the second branch.
    // By construction the path we still have to take is the '1' path.
    // In the literare this variable is usually called 'last_zero'.
    last-unexplored-branch := -1
    // Keeps track of the last bit position where we branched and still have to
    // take the second branch.
    // This variable (contrary to 'last_branch') is only used for the family bits
    // (the first 8 bits).
    last-unexplored-family-branch := -1
    // Keeps track of the last branching point of a previous iteration.
    // We are going to take the same path up to this point.
    // In the literature this variable is usually called 'last_discrepancy'.
    // This variable is updated once all 64 bits of a device id have been found.
    previous-last-unexplored-branch := fixed-bits

    while true:
      if not reset: return

      write-byte (alarm-only ? COMMAND-ROM-SEARCH-ALARM_ : COMMAND-ROM-SEARCH_)

      for id-bit-position := 0; id-bit-position < 64; id-bit-position++:
        // Devices are supposed to reply to the search command (and
        // bit-selections below) by sending their ID bit, and the complement.
        // Since the one-wire bus is open-drain, 0 values win, and we can
        // detect collisions by reading to 0 bits.

        id-bit := read-bits 1
        id-complement-bit := read-bits 1

        if id-bit == 1 and id-complement-bit == 1:
          // No response.
          // The 'reset' indicated that a device was present, but nothing
          // responded. Similarly, we could be here, because there was a
          // collision, but then too, we should see a device.
          if not alarm-only: throw "BUS ERROR"
          // No device with an alarm.
          return

        if id-bit == 0 and id-complement-bit == 0:
          // Collision.
          if id-bit-position < previous-last-unexplored-branch:
            // Take the same path as the last time.
            id-bit = (id >> id-bit-position) & 1
          else if id-bit-position == previous-last-unexplored-branch:
            // We took '0' the first time. Now we take '1'.
            id-bit = 1
          else:
            // New discrepancy. Take '0' first.
            id-bit = 0

          if id-bit == 0:
            // Remember where we have an unexplored branch.
            last-unexplored-branch = id-bit-position
            if id-bit-position < 8:
              last-unexplored-family-branch = last-unexplored-branch

        // Update the id with the chosen bit.
        id &= ~(1 << id-bit-position)
        id |= id-bit << id-bit-position

        // Notify the devices of the choice.
        // All devices that have an id with a different bit are silent
        // from now on.
        write-bit id-bit

      crc := crc8 id
      if id >>> 56 != crc:
        throw "CRC ERROR"

      // We have found a device.
      block-result := block.call id

      // Continue with the next iteration, unless there is no branching
      // point left.
      if last-unexplored-branch == -1: return

      if block-result == SKIP-FAMILY:
        previous-last-unexplored-branch = last-unexplored-family-branch
      else:
        previous-last-unexplored-branch = last-unexplored-branch
      last-unexplored-branch = -1
      last-unexplored-family-branch = -1

  static crc8 id/int:
    crc := crc.Crc.little-endian 8 --polynomial=0x8C
    data := ByteArray 7:
      byte := id & 0xFF
      id >>= 8
      byte
    crc.add data
    return crc.get-as-int

  static crc8 --bytes/ByteArray -> int:
    crc := crc.Crc.little-endian 8 --polynomial=0x8C
    crc.add bytes
    return crc.get-as-int

/**
A 1-wire protocol.
*/
interface Protocol:
  /** Exception thrown when the signal couldn't be decoded. */
  static INVALID-SIGNAL ::= "INVALID_SIGNAL"

  /**
  Constructs a new RMT-based protocol.

  See $RmtProtocol.constructor.
  */
  constructor pin/gpio.Pin
      --pull-up/bool
      --in-buffer-size/int=1024
      --in-channel-id/int?=null
      --out-channel-id/int?=null:
    return RmtProtocol pin
        --in-buffer-size=in-buffer-size
        --in-channel-id=in-channel-id
        --out-channel-id=out-channel-id
        --pull-up=pull-up

  /**
  Whether the protocol is closed.
  */
  is-closed -> bool

  /**
  Closes the protocol and releases the underlying resources.
  */
  close -> none

  /**
  Activates or deactivates power delivery to the bus.

  This is used to power devices that require more power than the bus can
    provide with just a pull-up resistor.

  When enabled, the open-drain is disabled, and devices on the bus can
    use up to 12mA of current delivered by the pin.
  */
  set-power new-value/bool -> none

  /**
  Writes $count bits from $value to the pin.
  */
  write-bits value/int count/int -> none

  /**
  Writes a single byte $value to the pin.
  */
  write-byte value/int -> none

  /**
  Writes all given $bytes to the pin.

  The $bytes are written individually, and not as a single bit sequence.
  */
  write bytes/ByteArray -> none

  /**
  Reads $count bits from the pin.

  The parameter $count must satisfy 0 <= $count <= 8. That is,
    at most one byte can be read at a time.
  */
  read-bits count/int -> int

  /**
  Reads a single byte from the pin.
  */
  read-byte -> int

  /**
  Reads $count bytes from the pin.

  The reading operation assumes that the bytes are sent individually.
  */
  read count/int -> ByteArray

  /**
  Sends a reset and returns whether any device is present.
  */
  reset -> bool

/**
The 1-wire protocol.
*/
class RmtProtocol implements Protocol:
  /*
  Timings: https://www.maximintegrated.com/en/design/technical-documents/app-notes/1/126.html

  The timings are giving as constants A, B, ... which have been incorporated into
    constant names below.
  */

  // Constant H from the application note.
  static RESET-LOW_ ::= 480
  // Constant I from the application note.
  static RESET-HIGH-BEFORE-SAMPLE_ ::= 70
  // Constant J from the application note.
  static RESET-HIGH-AFTER-SAMPLE_ ::= 410
  static RESET-HIGH_ ::= RESET-HIGH-BEFORE-SAMPLE_ + RESET-HIGH-AFTER-SAMPLE_
  // While resetting the idle threshold needs to be higher than any of the
  //   timings above.
  static RESET-IDLE-THRESHOLD_ ::= 480 + 50

  // IO_TIME_SLOT is the same for Write 1, Write 0, and Read.
  static IO-TIME-SLOT_ ::= 70

  // Read consists of pulling the line low for 6us, then waiting for 9us, before sampling.
  // Finally, the line should be kept high for another 55us.
  // Constant A from the application note.
  static READ-LOW_ ::= 6
  // Constant E from the application note.
  // The constant E in the application note is 9µs, but in many cases it might take
  // more time for the pull-up resistor to bring the line high again.
  // We therefore wait for 9µs + 5µs before sampling.
  static READ-HIGH-BEFORE-SAMPLE_ ::= 14
  // Constant F from the application note.
  static READ-HIGH-AFTER-SAMPLE_ ::= 55
  static READ-HIGH_ ::= READ-HIGH-BEFORE-SAMPLE_ + READ-HIGH-AFTER-SAMPLE_

  // Writing a 0 consists of pulling the line low for 60us.
  // Constant C from the application note.
  static WRITE-0-LOW_ ::= 60
  // Writing a 1 consists of pulling the line low for 6us.
  // Constant A from the application note.
  static WRITE-1-LOW_ ::= 6

  // Idle threshold.
  // Needs to be larger than any duration occurring during write slots.
  // We need to change the threshold when resetting as the reset time
  //   is significantly higher.
  static IDLE-THRESHOLD_ ::= IO-TIME-SLOT_ + 5

  static SIGNALS-PER-BIT_ ::= 2
  static SIGNALS-PER-BYTE_ ::= BITS-PER-BYTE * SIGNALS-PER-BIT_

  static RESET-RESPONSE-TIMEOUT-MS_ ::= 500

  pin_ /gpio.Pin
  channel-in_  /rmt.Channel? := ?
  channel-out_ /rmt.Channel? := ?

  /**
  Constructs a 1-Wire protocol using RMT channels.

  Configures the channels and the underlying pin for 1-wire.

  If $pull-up is true then the pin's pull-up resistor is enabled.

  # Advanced
  The $in-buffer-size should be left unchanged unless the protocol requires
    many bytes to be read in sequence without allowing any pause.
  Generally, it is recommended to just split read operations into managable chunks.

  If no $in-channel-id and $out-channel-id is provided then the first free RMT channels
    are used. This is almost always the correct choice. See $(rmt.Channel.constructor pin) for
    use cases when this is not the case.
  */
  constructor pin/gpio.Pin
      --pull-up/bool
      --in-buffer-size/int=1024
      --in-channel-id/int?=null
      --out-channel-id/int?=null:
    pin_ = pin

    // The default is slightly above 1us. For 1-wire we prefer a more sensitive filter.
    filter-ticks-threshold := 30

    // Output channel must be configured before the input channel for
    // `make_bidirectional` to work
    channel-out_ = rmt.Channel --output pin --channel-id=out-channel-id
        --idle-level=1
    channel-in_ = rmt.Channel --input pin --channel-id=in-channel-id
        --filter-ticks-threshold=filter-ticks-threshold
        --buffer-size=in-buffer-size
        --idle-threshold=IDLE-THRESHOLD_

    rmt.Channel.make-bidirectional --in=channel-in_ --out=channel-out_ --pull-up=pull-up

  constructor.test_:
    pin_ = gpio.VirtualPin:: null
    channel-in_ = null
    channel-out_ = null

  /**
  Whether the protocol is closed.
  */
  is-closed -> bool:
    return channel-in_ == null

  /**
  Closes the protocol and releases the underlying resources.
  */
  close -> none:
    if is-closed: return
    channel-in_.close
    channel-out_.close
    channel-in_ = null
    channel-out_ = null

  /**
  Enables or disables open-drain.

  When open-drain is disabled, the pin can source up to 12mA.
  */
  set-power new-value/bool:
    pin_.set-open-drain (not new-value)

  /**
  Decodes the given $signals to bytes.

  Decoding starts from the given $from byte and decodes $byte-count bytes.
  */
  static decode-signals-to-bytes_ signals/rmt.Signals --from/int=0 byte-count/int -> ByteArray:
    assert: 0 <= from
    assert: 0 <= byte-count

    if from + byte-count * SIGNALS-PER-BYTE_ > signals.size: throw Protocol.INVALID-SIGNAL

    write-signal-count := from * SIGNALS-PER-BYTE_
    return ByteArray byte-count:
      decode-signals-to-bits_ signals
          --from=(write-signal-count + it * SIGNALS-PER-BYTE_)

  static encode-read-signals_ --bit-count/int -> rmt.Signals:
    signals := rmt.Signals (bit-count * SIGNALS-PER-BIT_)
    bit-count.repeat:
      i := it * SIGNALS-PER-BIT_
      signals.set i --period=READ-LOW_ --level=0
      signals.set (i + 1) --period=READ-HIGH_ --level=1
    return signals

  /**
  Writes $count bits from $value to the pin.
  */
  write-bits value/int count/int -> none:
    signals := encode-write-signals_ value --count=count
    channel-out_.write signals

  /**
  Writes a single byte $value to the pin.
  */
  write-byte value/int -> none:
    write-bits value BITS-PER-BYTE

  /**
  Writes all given $bytes to the pin.

  The $bytes are written individually, and not as a single bit sequence.
  */
  write bytes/ByteArray -> none:
    bytes.do: write-byte it

  /**
  Encodes the given integer or byte array to a sequence of signals.

  The $bits-or-bytes must be either an integer, in which case the $count must be given.
  If $bits-or-bytes is a byte array, then the $count must be equal to $bits-or-bytes * 8.
  */
  static encode-write-signals_ bits-or-bytes/any --count/int -> rmt.Signals:
    signals := rmt.Signals (count * SIGNALS-PER-BIT_)

    if bits-or-bytes is int:
      encode-write-signals_ signals bits-or-bytes --count=count
    else:
      assert: count == bits-or-bytes.size * BITS-PER-BYTE
      offset := 0
      bits-or-bytes.do:
        encode-write-signals_ signals it --from=offset --count=BITS-PER-BYTE
        offset += SIGNALS-PER-BYTE_

    return signals

  static encode-write-signals_ signals/rmt.Signals bits/int --from/int=0 --count/int -> none:
    write-signal-count := count * SIGNALS-PER-BIT_
    assert: 0 <= from < signals.size
    assert: from + write-signal-count <= signals.size
    count.repeat:
      // Write the lowest bit.
      delay := ?
      if bits & 0x01 == 1:
        delay = WRITE-1-LOW_
      else:
        delay = WRITE-0-LOW_
      i := from + it * SIGNALS-PER-BIT_
      signals.set i --period=delay --level=0
      signals.set (i + 1) --period=(IO-TIME-SLOT_ - delay) --level=1
      bits = bits >> 1

  /**
  Reads $count bits from the pin.

  The parameter $count must satisfy 0 <= $count <= 64.
  */
  read-bits count/int -> int:
    if not 0 <= count <= 64: throw "INVALID_ARGUMENT"
    read-signals := encode-read-signals_ --bit-count=count
    channel-in_.start-reading
    channel-out_.write read-signals
    received-signals := channel-in_.read
    channel-in_.stop-reading
    return decode-signals-to-bits_ received-signals --bit-count=count

  /**
  Reads a single byte from the pin.
  */
  read-byte -> int:
    return read-bits BITS-PER-BYTE

  /**
  Reads $count bytes from the pin.

  The reading operation assumes that the bytes are sent individually.
  */
  read count/int -> ByteArray:
    return ByteArray count: read-byte

  static decode-signals-to-bits_ signals/rmt.Signals --from/int=0 --bit-count/int=8 -> int:
    assert: 0 <= from
    if not 0 <= bit-count <= 64: throw "INVALID_ARGUMENT"
    if from + bit-count * SIGNALS-PER-BIT_ > signals.size: throw Protocol.INVALID-SIGNAL

    inverted-result := 0
    bit-count.repeat:
      i := from + it * 2
      if (signals.level i) != 0: throw Protocol.INVALID-SIGNAL
      if (signals.level i + 1) != 1: throw Protocol.INVALID-SIGNAL

      inverted-result <<= 1
      if (signals.period i) < READ-HIGH-BEFORE-SAMPLE_: inverted-result |= 1

    result := 0
    bit-count.repeat:
      result <<= 1
      result |= inverted-result & 0x01
      inverted-result >>= 1

    return result

  /**
  Sends a reset to the receiver and reads whether a receiver is present.
  */
  reset -> bool:
    old-threshold := channel-in_.idle-threshold
    channel-in_.idle-threshold = RESET-IDLE-THRESHOLD_
    periods := [
      RESET-LOW_,
      RESET-HIGH_,
    ]
    try:
      signals := rmt.Signals.alternating --first-level=0 periods

      channel-in_.start-reading
      channel-out_.write signals
      catch:
        with-timeout --ms=RESET-RESPONSE-TIMEOUT-MS_:
          received-signals := channel-in_.read

          return received-signals.size >= 3 and
            // We observe the first low pulse that we sent.
            (received-signals.level 0) == 0 and (RESET-LOW_ - 2) <= (received-signals.period 0) <= (RESET-LOW_ + 10) and
            // We release the pin so it becomes high.
            (received-signals.level 1) == 1 and (received-signals.period 1) > 0 and
            // The receiver signals its presence.
            // In theory we could ensure that we sample at the right time, but it doesn't
            //   really matter. Once we have the device pull low, we should be OK.
            (received-signals.level 2) == 0 and (received-signals.period 2) > 0
      // If we are here, we had a timeout.
      return false
    finally:
      channel-in_.idle-threshold = old-threshold
