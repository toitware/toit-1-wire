// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import rmt
import gpio

/**
Support for 1-wire protocol.

The 1-wire protocol is implemented with ESP32's hardware supported RMT module.
*/

/**
A 1-wire bus.
*/
class Bus:
  static COMMAND_SELECT_ ::= 0x55
  static COMMAND_SKIP_   ::= 0xCC
  static COMMAND_SEARCH_ ::= 0xF0
  static COMMAND_SEARCH_ALARM_ ::= 0xEC

  /**
  Marker to indicate that all devices of the given family should be skipped
    during the search.

  A block should return this value when no other device of the family should
    be given to the block.
  */
  static SKIP_FAMILY ::= Object

  protocol_/Protocol? := ?

  /**
  Constructs a 1-wire bus using the given $protocol.
  */
  constructor.protocol protocol:
    protocol_ = protocol

  /**
  Constructs a 1-wire bus for the given $pin.

  This constructor uses the default parameters for the protocol. Use
    $Bus.protocol if you need to customize the protocol.
  */
  constructor pin/gpio.Pin:
    protocol_ = Protocol pin

  /** Whether this bus is closed. */
  is_closed -> bool:
    return protocol_ == null

  /**
  Closes this bus and releases the underlying resources.
  */
  close:
    if protocol_:
      protocol_.close
      protocol_ = null

  // /**
  // Resets the bus.

  // Returns whether a device is attached to the bus.
  // */
  // reset -> bool:
  //   return protocol_.reset

  /**
  Selects the device with the given $device_id.

  The $device_id is a byte array of length 8.
  */
  select device_id/int -> none:
    if not protocol_.reset: throw "NO DEVICE"
    protocol_.write_byte COMMAND_SELECT_
    protocol_.write_bits device_id 64

  /**
  Skips the device selection step.

  This is useful when there is only one device on the bus, or
    if multiple devices are addressed at the same time.
  */
  skip -> none:
    if not protocol_.reset: throw "NO DEVICE"
    protocol_.write_byte COMMAND_SKIP_

  /**
  Searches for devices on the bus and calls the $block with
    the device id of each found device.

  If $alarm_only is set, then searches for devices that have
    triggered an alarm.

  If a $family is given, then only devices with that family
    are searched for.
  */
  do --alarm_only/bool=false --family/int?=null [block] -> none:
    if family:
      // Start the search with the family id.
      // By setting the previous_last_unexplored_branch to 64 (any higher value
      // would work too), we are letting
      // the search always take the '0' branch for the non-family bits.
      // Note that the search overwrites the id for non-collision bits.
      // As a consequence, the search will find the first device with an
      // id that is greater or equal to the family id.
      search_
          --alarm_only=alarm_only
          --start_id=family
          --fixed_bits=8
          : | id |
            if id & 0xFF != family: return
            block.call id
    else:
      search_ --alarm_only=alarm_only block

  /**
  Searches for the device with the given id.

  Returns true if the device responded.
  */
  ping id/int -> bool:
    search_ --no-alarm_only --start_id=id --fixed_bits=64: | found_id |
      return found_id == id
    return false

  search_ --alarm_only/bool --start_id/int=0 --fixed_bits/int=-1 [block]-> none:
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
    id := start_id

    // Keeps track of the last bit position where we branched and still have to
    // take the second branch.
    // By construction the path we still have to take is the '1' path.
    // In the literare this variable is usually called 'last_zero'.
    last_unexplored_branch := -1
    // Keeps track of the last bit position where we branched and still have to
    // take the second branch.
    // This variable (contrary to 'last_branch') is only used for the family bits
    // (the first 8 bits).
    last_unexplored_family_branch := -1
    // Keeps track of the last branching point of a previous iteration.
    // We are going to take the same path up to this point.
    // In the literature this variable is usually called 'last_discrepancy'.
    // This variable is updated once all 64 bits of a device id have been found.
    previous_last_unexplored_branch := fixed_bits

    while true:
      if not protocol_.reset: return

      protocol_.write_byte (alarm_only ? COMMAND_SEARCH_ALARM_ : COMMAND_SEARCH_)

      for id_bit_position := 0; id_bit_position < 64; id_bit_position++:
        // Devices are supposed to reply to the search command (and
        // bit-selections below) by sending their ID bit, and the complement.
        // Since the one-wire bus is open-drain, 0 values win, and we can
        // detect collisions by reading to 0 bits.

        id_bit := protocol_.read_bits 1
        id_complement_bit := protocol_.read_bits 1

        if id_bit == 1 and id_complement_bit == 1:
          // No response.
          // The 'reset' indicated that a device was present, but nothing
          // responded. Similarly, we could be here, because there was a
          // collision, but then too, we should see a device.
          throw "BUS ERROR"

        if id_bit == 0 and id_complement_bit == 0:
          // Collision.
          if id_bit_position < previous_last_unexplored_branch:
            // Take the same path as the last time.
            id_bit = (id >> id_bit_position) & 1
          else if id_bit_position == previous_last_unexplored_branch:
            // We took '0' the first time. Now we take '1'.
            id_bit = 1
          else:
            // New discrepancy. Take '0' first.
            id_bit = 0

          if id_bit == 0:
            // Remember where we have an unexplored branch.
            last_unexplored_branch = id_bit_position
            if id_bit_position < 8:
              last_unexplored_family_branch = last_unexplored_branch

        // Update the id with the chosen bit.
        id &= ~(1 << id_bit_position)
        id |= id_bit << id_bit_position

        // Notify the devices of the choice.
        // All devices that have an id with a different bit are silent
        // from now on.
        protocol_.write_bits id_bit 1

      // We have found a device.
      block_result := block.call id

      // Continue with the next iteration, unless there is no branching
      // point left.
      if last_unexplored_branch == -1: return

      if block_result == SKIP_FAMILY:
        previous_last_unexplored_branch = last_unexplored_family_branch
      else:
        previous_last_unexplored_branch = last_unexplored_branch
      last_unexplored_branch = -1
      last_unexplored_family_branch = -1

/**
A 1-wire protocol.
*/
interface Protocol:
  /** Exception thrown when the signal couldn't be decoded. */
  static INVALID_SIGNAL ::= "INVALID_SIGNAL"

  /**
  Constructs a new RMT-based protocol.

  See $RmtProtocol.constructor.
  */
  constructor pin/gpio.Pin --in_buffer_size/int=1024 --in_channel_id/int?=null --out_channel_id/int?=null:
    return RmtProtocol pin --in_buffer_size=in_buffer_size --in_channel_id=in_channel_id --out_channel_id=out_channel_id

  /**
  Whether the protocol is closed.
  */
  is_closed -> bool

  /**
  Closes the protocol and releases the underlying resources.
  */
  close -> none

  /**
  Writes $count bits from $value to the pin.
  */
  write_bits value/int count/int -> none

  /**
  Writes a single byte $value to the pin.
  */
  write_byte value/int -> none

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
  read_bits count/int -> int

  /**
  Reads a single byte from the pin.
  */
  read_byte -> int

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
  static RESET_LOW_ ::= 480
  // Constant I from the application note.
  static RESET_HIGH_BEFORE_SAMPLE_ ::= 70
  // Constant J from the application note.
  static RESET_HIGH_AFTER_SAMPLE_ ::= 410
  static RESET_HIGH_ ::= RESET_HIGH_BEFORE_SAMPLE_ + RESET_HIGH_AFTER_SAMPLE_
  // While resetting the idle threshold needs to be higher than any of the
  //   timings above.
  static RESET_IDLE_THRESHOLD_ ::= 480 + 50

  // IO_TIME_SLOT is the same for Write 1, Write 0, and Read.
  static IO_TIME_SLOT_ ::= 70

  // Read consists of pulling the line low for 6us, then waiting for 9us, before sampling.
  // Finally, the line should be kept high for another 55us.
  // Constant A from the application note.
  static READ_LOW_ ::= 6
  // Constant E from the application note.
  static READ_HIGH_BEFORE_SAMPLE_ ::= 9
  // Constant F from the application note.
  static READ_HIGH_AFTER_SAMPLE_ ::= 55
  static READ_HIGH_ ::= READ_HIGH_BEFORE_SAMPLE_ + READ_HIGH_AFTER_SAMPLE_

  // Writing a 0 consists of pulling the line low for 60us.
  // Constant C from the application note.
  static WRITE_0_LOW_ ::= 60
  // Writing a 1 consists of pulling the line low for 6us.
  // Constant A from the application note.
  static WRITE_1_LOW_ ::= 6

  // Idle threshold.
  // Needs to be larger than any duration occurring during write slots.
  // We need to change the threshold when resetting as the reset time
  //   is significantly higher.
  static IDLE_THRESHOLD_ ::= IO_TIME_SLOT_ + 5

  static SIGNALS_PER_BIT_ ::= 2
  static SIGNALS_PER_BYTE_ ::= BITS_PER_BYTE * SIGNALS_PER_BIT_

  static RESET_RESPONSE_TIMEOUT_MS_ ::= 500

  channel_in_  /rmt.Channel? := ?
  channel_out_ /rmt.Channel? := ?

  /**
  Constructs a 1-Wire protocol using RMT channels.

  Configures the channels and the underlying pin for 1-wire.

  # Advanced
  The $in_buffer_size should be left unchanged unless the protocol requires
    many bytes to be read in sequence without allowing any pause.
  Generally, it is recommended to just split read operations into managable chunks.

  If no $in_channel_id and $out_channel_id is provided then the first free RMT channels
    are used. This is almost always the correct choice. See $(rmt.Channel.constructor pin) for
    use cases when this is not the case.
  */
  constructor pin/gpio.Pin --in_buffer_size/int=1024 --in_channel_id/int?=null --out_channel_id/int?=null:
    // The default is slightly above 1us. For 1-wire we prefer a more sensitive filter.
    filter_ticks_threshold := 30

    // Output channel must be configured before the input channel for
    // `make_bidirectional` to work
    channel_out_ = rmt.Channel --output pin --channel_id=out_channel_id
        --idle_level=1
    channel_in_ = rmt.Channel --input pin --channel_id=in_channel_id
        --filter_ticks_threshold=filter_ticks_threshold
        --buffer_size=in_buffer_size
        --idle_threshold=IDLE_THRESHOLD_

    rmt.Channel.make_bidirectional --in=channel_in_ --out=channel_out_

  constructor.test_:
    channel_in_ = null
    channel_out_ = null

  /**
  Whether the protocol is closed.
  */
  is_closed -> bool:
    return channel_in_ == null

  /**
  Closes the protocol and releases the underlying resources.
  */
  close -> none:
    if is_closed: return
    channel_in_.close
    channel_out_.close
    channel_in_ = null
    channel_out_ = null

  /**
  Decodes the given $signals to bytes.

  Decoding starts from the given $from byte and decodes $byte_count bytes.
  */
  static decode_signals_to_bytes_ signals/rmt.Signals --from/int=0 byte_count/int -> ByteArray:
    assert: 0 <= from
    assert: 0 <= byte_count

    if from + byte_count * SIGNALS_PER_BYTE_ > signals.size: throw Protocol.INVALID_SIGNAL

    write_signal_count := from * SIGNALS_PER_BYTE_
    return ByteArray byte_count:
      decode_signals_to_bits_ signals
          --from=(write_signal_count + it * SIGNALS_PER_BYTE_)

  static encode_read_signals_ --bit_count/int -> rmt.Signals:
    signals := rmt.Signals (bit_count * SIGNALS_PER_BIT_)
    bit_count.repeat:
      i := it * SIGNALS_PER_BIT_
      signals.set i --period=READ_LOW_ --level=0
      signals.set (i + 1) --period=READ_HIGH_ --level=1
    return signals

  /**
  Writes $count bits from $value to the pin.
  */
  write_bits value/int count/int -> none:
    signals := encode_write_signals_ value --count=count
    channel_out_.write signals

  /**
  Writes a single byte $value to the pin.
  */
  write_byte value/int -> none:
    write_bits value BITS_PER_BYTE

  /**
  Writes all given $bytes to the pin.

  The $bytes are written individually, and not as a single bit sequence.
  */
  write bytes/ByteArray -> none:
    bytes.do: write_byte it

  /**
  Encodes the given integer or byte array to a sequence of signals.

  The $bits_or_bytes must be either an integer, in which case the $count must be given.
  If $bits_or_bytes is a byte array, then the $count must be equal to $bits_or_bytes * 8.
  */
  static encode_write_signals_ bits_or_bytes/any --count/int -> rmt.Signals:
    signals := rmt.Signals (count * SIGNALS_PER_BIT_)

    if bits_or_bytes is int:
      encode_write_signals_ signals bits_or_bytes --count=count
    else:
      assert: count == bits_or_bytes.size * BITS_PER_BYTE
      offset := 0
      bits_or_bytes.do:
        encode_write_signals_ signals it --from=offset --count=BITS_PER_BYTE
        offset += SIGNALS_PER_BYTE_

    return signals

  static encode_write_signals_ signals/rmt.Signals bits/int --from/int=0 --count/int -> none:
    write_signal_count := count * SIGNALS_PER_BIT_
    assert: count <= 8
    assert: 0 <= from < signals.size
    assert: from + write_signal_count < signals.size
    count.repeat:
      // Write the lowest bit.
      delay := ?
      if bits & 0x01 == 1:
        delay = WRITE_1_LOW_
      else:
        delay = WRITE_0_LOW_
      i := from + it * SIGNALS_PER_BIT_
      signals.set i --period=delay --level=0
      signals.set (i + 1) --period=(IO_TIME_SLOT_ - delay) --level=1
      bits = bits >> 1

  /**
  Reads $count bits from the pin.

  The parameter $count must satisfy 0 <= $count <= 8. That is,
    at most one byte can be read at a time.
  */
  read_bits count/int -> int:
    read_signals := encode_read_signals_ --bit_count=count
    channel_in_.start_reading
    channel_out_.write read_signals
    received_signals := channel_in_.read
    channel_in_.stop_reading
    return decode_signals_to_bits_ received_signals --bit_count=count

  /**
  Reads a single byte from the pin.
  */
  read_byte -> int:
    return read_bits BITS_PER_BYTE

  /**
  Reads $count bytes from the pin.

  The reading operation assumes that the bytes are sent individually.
  */
  read count/int -> ByteArray:
    return ByteArray count: read_byte

  static decode_signals_to_bits_ signals/rmt.Signals --from/int=0 --bit_count/int=8 -> int:
    assert: 0 <= from
    assert: 0 <= bit_count <= 8
    if from + bit_count * SIGNALS_PER_BIT_ > signals.size: throw Protocol.INVALID_SIGNAL

    result := 0
    bit_count.repeat:
      i := from + it * 2
      if (signals.level i) != 0: throw Protocol.INVALID_SIGNAL
      if (signals.level i + 1) != 1: throw Protocol.INVALID_SIGNAL

      result = result >> 1
      if (signals.period i) < READ_HIGH_BEFORE_SAMPLE_: result = result | 0x80
    result = result >> (8 - bit_count)

    return result

  /**
  Sends a reset to the receiver and reads whether a receiver is present.
  */
  reset -> bool:
    old_threshold := channel_in_.idle_threshold
    channel_in_.idle_threshold = RESET_IDLE_THRESHOLD_
    periods := [
      RESET_LOW_,
      RESET_HIGH_,
    ]
    try:
      signals := rmt.Signals.alternating --first_level=0 periods

      channel_in_.start_reading
      channel_out_.write signals
      catch:
        with_timeout --ms=RESET_RESPONSE_TIMEOUT_MS_:
          received_signals := channel_in_.read

          return received_signals.size >= 3 and
            // We observe the first low pulse that we sent.
            (received_signals.level 0) == 0 and (RESET_LOW_ - 2) <= (received_signals.period 0) <= (RESET_LOW_ + 10) and
            // We release the pin so it becomes high.
            (received_signals.level 1) == 1 and (received_signals.period 1) > 0 and
            // The receiver signals its presence.
            // In theory we could ensure that we sample at the right time, but it doesn't
            //   really matter. Once we have the device pull low, we should be OK.
            (received_signals.level 2) == 0 and (received_signals.period 2) > 0
      // If we are here, we had a timeout.
      return false
    finally:
      channel_in_.idle_threshold = old_threshold
