// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import one-wire show *
import rmt
import expect show *

main:
  test-decode-signals-to-bits
  test-decode-signals-to-bytes
  test-encode-read-signals
  test-encode-write-signals

test-decode-signals-to-bits:
  signals := rmt.Signals.alternating --first-level=0 [
    24, 46,  // 0
    24, 46,  // 0
    24, 46,  // 0
    6,  64,  // 1
    6,  64,  // 1
    24, 46,  // 0
    6,  64,  // 1
    6,  64,  // 1
  ]
  expect-equals 0b11011000
    RmtProtocol.decode-signals-to-bits_ signals
  expect-equals 0b01101100
    RmtProtocol.decode-signals-to-bits_ signals --from=2 --bit-count=7
  expect-equals 0b0
    RmtProtocol.decode-signals-to-bits_ signals --from=0 --bit-count=0
  expect-equals 0b1
    RmtProtocol.decode-signals-to-bits_ signals --from=14 --bit-count=1

  // Decoding should start on a low edge (level = 0).
  expect-throw Protocol.INVALID-SIGNAL:
    RmtProtocol.decode-signals-to-bits_ signals --from=1 --bit-count=1

  expect-throw Protocol.INVALID-SIGNAL:
    RmtProtocol.decode-signals-to-bits_ signals --from=0 --bit-count=10

  signals = rmt.Signals 2
  signals.set 0 --period=0 --level=0
  signals.set 1 --period=0 --level=0
  // The low edge should be followed by a high edge (level = 1).
  expect-throw Protocol.INVALID-SIGNAL:
    RmtProtocol.decode-signals-to-bits_ signals --from=0 --bit-count=1

test-decode-signals-to-bytes:
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
  signals := rmt.Signals.alternating --first-level=0 periods

  expect-bytes-equal #[0xD8]
    RmtProtocol.decode-signals-to-bytes_ signals 1

  expect-bytes-equal #[0xCC]
    RmtProtocol.decode-signals-to-bytes_ signals --from=1 1

  expect-bytes-equal #[0xD8, 0xCC]
    RmtProtocol.decode-signals-to-bytes_ signals 2

  expect-bytes-equal #[]
    RmtProtocol.decode-signals-to-bytes_ signals 0

  expect-throw Protocol.INVALID-SIGNAL:
    RmtProtocol.decode-signals-to-bytes_ signals --from=1 2


  signals = rmt.Signals.alternating --first-level=0 []
  expect-bytes-equal #[]
    RmtProtocol.decode-signals-to-bytes_ signals 0

  expect-throw Protocol.INVALID-SIGNAL:
    RmtProtocol.decode-signals-to-bytes_ signals --from=0 1

  expect-throw Protocol.INVALID-SIGNAL:
    RmtProtocol.decode-signals-to-bytes_ signals --from=1 1

test-encode-read-signals:
  signals := RmtProtocol.encode-read-signals_ --bit-count=8

  8.repeat:
    expect-equals 0 (signals.level it * 2)
    expect-equals RmtProtocol.READ-LOW_ (signals.period it * 2)
    expect-equals 1 (signals.level it * 2 + 1)
    expect-equals RmtProtocol.READ-HIGH_ (signals.period it * 2 + 1)

test-encode-write-signals:
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
  signals := RmtProtocol.encode-write-signals_ 0xDA --count=16
  8.repeat:
    expect-equals 0
      signals.level it * 2
    expect-equals periods[it * 2]
      signals.period it * 2
    expect-equals 1
      signals.level it * 2 + 1
    expect-equals periods[it * 2 + 1]
      signals.period it * 2 + 1

  signals = rmt.Signals 16
  RmtProtocol.encode-write-signals_ signals 0xDA --count=6
  6.repeat:
    expect-equals 0
      signals.level it * 2
    expect-equals periods[it * 2]
      signals.period it * 2
    expect-equals 1
      signals.level it * 2 + 1
    expect-equals periods[it * 2 + 1]
      signals.period it * 2 + 1
