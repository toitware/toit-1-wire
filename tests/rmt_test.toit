// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import one_wire show *
import rmt
import expect show *

main:
  test_decode_signals_to_bits
  test_decode_signals_to_bytes
  test_encode_read_signals
  test_encode_write_signals

test_decode_signals_to_bits:
  signals := rmt.Signals.alternating --first_level=0 [
    24, 46,  // 0
    24, 46,  // 0
    24, 46,  // 0
    6,  64,  // 1
    6,  64,  // 1
    24, 46,  // 0
    6,  64,  // 1
    6,  64,  // 1
  ]
  expect_equals 0b11011000
    RmtProtocol.decode_signals_to_bits_ signals
  expect_equals 0b01101100
    RmtProtocol.decode_signals_to_bits_ signals --from=2 --bit_count=7
  expect_equals 0b0
    RmtProtocol.decode_signals_to_bits_ signals --from=0 --bit_count=0
  expect_equals 0b1
    RmtProtocol.decode_signals_to_bits_ signals --from=14 --bit_count=1

  // Decoding should start on a low edge (level = 0).
  expect_throw Protocol.INVALID_SIGNAL:
    RmtProtocol.decode_signals_to_bits_ signals --from=1 --bit_count=1

  expect_throw Protocol.INVALID_SIGNAL:
    RmtProtocol.decode_signals_to_bits_ signals --from=0 --bit_count=10

  signals = rmt.Signals 2
  signals.set 0 --period=0 --level=0
  signals.set 1 --period=0 --level=0
  // The low edge should be followed by a high edge (level = 1).
  expect_throw Protocol.INVALID_SIGNAL:
    RmtProtocol.decode_signals_to_bits_ signals --from=0 --bit_count=1

test_decode_signals_to_bytes:
  periods := [
      // 0xD8
      24, 46,  // 0
      24, 46,  // 0
      24, 46,  // 0
      6,  64,  // 1
      6,  64,  // 1
      24, 46,  // 0
      6,  64,  // 1
      6,  64,  // 1
      // 0xCC
      24, 46,  // 0
      24, 46,  // 0
      6,  64,  // 1
      6,  64,  // 1
      24, 46,  // 0
      24, 46,  // 0
      6,  64,  // 1
      6,  64,  // 1
    ]
  signals := rmt.Signals.alternating --first_level=0 periods

  expect_bytes_equal #[0xD8]
    RmtProtocol.decode_signals_to_bytes_ signals 1

  expect_bytes_equal #[0xCC]
    RmtProtocol.decode_signals_to_bytes_ signals --from=1 1

  expect_bytes_equal #[0xD8, 0xCC]
    RmtProtocol.decode_signals_to_bytes_ signals 2

  expect_bytes_equal #[]
    RmtProtocol.decode_signals_to_bytes_ signals 0

  expect_throw Protocol.INVALID_SIGNAL:
    RmtProtocol.decode_signals_to_bytes_ signals --from=1 2


  signals = rmt.Signals.alternating --first_level=0 []
  expect_bytes_equal #[]
    RmtProtocol.decode_signals_to_bytes_ signals 0

  expect_throw Protocol.INVALID_SIGNAL:
    RmtProtocol.decode_signals_to_bytes_ signals --from=0 1

  expect_throw Protocol.INVALID_SIGNAL:
    RmtProtocol.decode_signals_to_bytes_ signals --from=1 1

test_encode_read_signals:
  signals := RmtProtocol.encode_read_signals_ --bit_count=8

  8.repeat:
    expect_equals 0 (signals.level it * 2)
    expect_equals RmtProtocol.READ_LOW_ (signals.period it * 2)
    expect_equals 1 (signals.level it * 2 + 1)
    expect_equals RmtProtocol.READ_HIGH_ (signals.period it * 2 + 1)

test_encode_write_signals:
  periods := [
    // 0xDA
    60, 10,  // 0
    6,  64,  // 1
    60, 10,  // 0
    6,  64,  // 1
    6,  64,  // 1
    60, 10,  // 0
    6,  64,  // 1
    6,  64,  // 1
  ]
  signals := RmtProtocol.encode_write_signals_ 0xDA --count=16
  8.repeat:
    expect_equals 0
      signals.level it * 2
    expect_equals periods[it * 2]
      signals.period it * 2
    expect_equals 1
      signals.level it * 2 + 1
    expect_equals periods[it * 2 + 1]
      signals.period it * 2 + 1

  signals = rmt.Signals 16
  RmtProtocol.encode_write_signals_ signals 0xDA --count=6
  6.repeat:
    expect_equals 0
      signals.level it * 2
    expect_equals periods[it * 2]
      signals.period it * 2
    expect_equals 1
      signals.level it * 2 + 1
    expect_equals periods[it * 2 + 1]
      signals.period it * 2 + 1
