// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import rmt

/**
Support for 1-wire protocol.

The 1-wire protocol is implemented with ESP32's hardware supported RMT module.
*/

/**
The 1-wire protocol.

Use $read_bits and $write_bits to read or write bytes to the receiver.

Use $write_then_read to write bytes to the receiver and then immediately start reading.

Use $reset to reset the receiver.
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

  rx_channel_/rmt.Channel
  tx_channel_/rmt.Channel

  /**
  Constructs a 1-Wire protocol using the given $rx and $tx channel.

  Configures the channels and the underlying pin for 1-wire.

  # Advanced
  The $rx_buffer_size should be left unchanged unless the protocol requires
    many bytes to be read in sequence without allowing any pause.
  Generally, it is recommended to just split read operations into managable chunks.
  */
  constructor --rx/rmt.Channel --tx/rmt.Channel --rx_buffer_size/int=1024:
    rx_channel_ = rx
    tx_channel_ = tx
    tx_channel_.config_tx --idle_level=1
    // The default is slightly above 1us. For 1-wire we prefer a more sensitive filter.
    filter_ticks_threshold := 30
    rx_channel_.config_rx
        --filter_ticks_thresh=filter_ticks_threshold
        --idle_threshold=IDLE_THRESHOLD_
        --rx_buffer_size=rx_buffer_size

    rmt.rmt_config_bidirectional_pin_ rx_channel_.pin.num tx_channel_.num

  /**
  Writes the given bytes and then reads the given $byte_count number of bytes.

  Should be used when the read must happen shortly after the write as there
    is little interruption between the write and the read.

  The function first writes the $bytes, waiting for the write to complete.
    Then it starts reading the $byte_count. This sequence happens in C code
    and the switch from writing to reading generally takes between 100 and 150us.
  */
  write_then_read bytes/ByteArray byte_count/int -> ByteArray:
    write_signals := encode_write_signals_ bytes --count=(bytes.size * BITS_PER_BYTE)
    read_signals := encode_read_signals_ --bit_count=(byte_count * BITS_PER_BYTE)

    expected_bytes_count := (bytes.size + byte_count) * SIGNALS_PER_BYTE_ * rmt.BYTES_PER_SIGNAL
    received_signals := rmt.transmit_and_receive --rx=rx_channel_ --tx=tx_channel_ --transmit=write_signals --receive=read_signals expected_bytes_count
    return decode_signals_to_bytes_ received_signals byte_count

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
    rmt.transmit tx_channel_ signals

  write_byte value/int -> none:
    write_bits value BITS_PER_BYTE

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
    write_signals := rmt.Signals 0
    signals := rmt.transmit_and_receive --rx=rx_channel_ --tx=tx_channel_ --transmit=write_signals --receive=read_signals
        (count + 1) * SIGNALS_PER_BIT_ * rmt.BYTES_PER_SIGNAL
    return decode_signals_to_bits_ signals --bit_count=count

  read_byte -> int:
    return read_bits BITS_PER_BYTE

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
    old_threshold := rx_channel_.idle_threshold
    rx_channel_.idle_threshold = RESET_IDLE_THRESHOLD_
    periods := [
      RESET_LOW_,
      RESET_HIGH_,
    ]
    try:
      received_signals := rmt.transmit_and_receive --rx=rx_channel_ --tx=tx_channel_
          --transmit=rmt.Signals 0
          --receive=rmt.Signals.alternating --first_level=0 periods
          4 * rmt.BYTES_PER_SIGNAL
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
      rx_channel_.idle_threshold = old_threshold
