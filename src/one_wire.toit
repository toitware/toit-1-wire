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
The 1-wire protocol.
*/
class Protocol:
  // Exception thrown when the signal couldn't be decoded.
  static INVALID_SIGNAL ::= "INVALID_SIGNAL"

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

  channel_in_  /rmt.Channel
  channel_out_ /rmt.Channel

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
    channel_in_ = rmt.Channel --input pin --channel_id=in_channel_id
        --filter_ticks_threshold=filter_ticks_threshold
        --buffer_size=in_buffer_size
        --idle_threshold=IDLE_THRESHOLD_

    rmt.Channel.make_bidirectional --in=channel_in_ --out=channel_out_

  /**
  Decodes the given $signals to bytes.

  Decoding starts from the given $from byte and decodes $byte_count bytes.
  */
  decode_signals_to_bytes_ signals/rmt.Signals --from/int=0 byte_count/int -> ByteArray:
    assert: 0 <= from
    assert: 0 <= byte_count

    if from + byte_count * SIGNALS_PER_BYTE_ > signals.size: throw INVALID_SIGNAL

    write_signal_count := from * SIGNALS_PER_BYTE_
    result := ByteArray byte_count: 0
    byte_count.repeat:
      result[it] = decode_signals_to_bits_ signals --from=write_signal_count + it * SIGNALS_PER_BYTE_
    return result

  encode_read_signals_ --bit_count/int -> rmt.Signals:
    signals := rmt.Signals (bit_count * SIGNALS_PER_BIT_)
    bit_count.repeat:
      i := it * SIGNALS_PER_BIT_
      signals.set i --period=READ_LOW_ --level=0
      signals.set (i + 1) --period=READ_HIGH_ --level=1
    return signals

  /**
  Writes $count bits from $value to the receiver.
  */
  write_bits value/int count/int -> none:
    signals := encode_write_signals_ value --count=count
    channel_out_.write signals

  write_byte value/int -> none:
    write_bits value BITS_PER_BYTE

  write bytes/ByteArray -> none:
    bytes.do: write_byte it

  /**
  Encodes the given integer or byte array to a sequence of signals.

  The $bits_or_bytes must be either an integer, in which case the $count must be given.
  If $bits_or_bytes is a byte array, then the $count must be equal to $bits_or_bytes * 8.
  */
  encode_write_signals_ bits_or_bytes/any --count/int -> rmt.Signals:
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

  encode_write_signals_ signals/rmt.Signals bits/int --from/int=0 --count/int -> none:
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
  Reads $count bits from the receiver.

  Can at most read one byte, so $count must satisfy $count <= 8.
  */
  read_bits count/int -> int:
    read_signals := encode_read_signals_ --bit_count=count
    channel_in_.start_reading
    channel_out_.write read_signals
    received_signals := channel_in_.read
    channel_in_.stop_reading
    return decode_signals_to_bits_ received_signals --bit_count=count

  read_byte -> int:
    return read_bits BITS_PER_BYTE

  read count/int -> ByteArray:
    result := ByteArray count: 0
    count.repeat:
      result[it] = read_byte
    return result

  decode_signals_to_bits_ signals/rmt.Signals --from/int=0 --bit_count/int=8 -> int:
    assert: 0 <= from
    assert: 0 <= bit_count <= 8
    if from + bit_count * SIGNALS_PER_BIT_ > signals.size: throw INVALID_SIGNAL

    result := 0
    bit_count.repeat:
      i := from + it * 2
      if (signals.level i) != 0: throw INVALID_SIGNAL
      if (signals.level i + 1) != 1: throw INVALID_SIGNAL

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
      received_signals := channel_in_.read

      return received_signals.size >= 3 and
        // We observe the first low pulse that we sent.
        (received_signals.level 0) == 0 and (RESET_LOW_ - 2) <= (received_signals.period 0) <= (RESET_LOW_ + 10) and
        // We release the bus so it becomes high.
        (received_signals.level 1) == 1 and (received_signals.period 1) > 0 and
        // The receiver signals its presence.
        // In theory we could ensure that we sample at the right time, but it doesn't
        //   really matter. Once we have the device pull low, we should be OK.
        (received_signals.level 2) == 0 and (received_signals.period 2) > 0
    finally:
      channel_in_.idle_threshold = old_threshold
