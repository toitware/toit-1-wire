// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import one-wire.hardware show HardwareProtocol
import expect show *
import gpio
import system

main:
  if system.platform != system.PLATFORM-FREERTOS:
    expect-equals false (HardwareProtocol.is-supported 19)
    expect-error "UNSUPPORTED": HardwareProtocol 19
    print "Hardware backend absence on host PASS"
    return
  expect-equals true (HardwareProtocol.is-supported 19)
  expect-equals false (HardwareProtocol.is-supported 18)
  expect-error "INVALID_ARGUMENT": HardwareProtocol 19 --timeout-ms=0
  protocol := HardwareProtocol 19 --pull-up
  try:
    expect-error "ALREADY_IN_USE": HardwareProtocol 19
    expect-error "ALREADY_IN_USE": HardwareProtocol 17
    expect-error "ALREADY_IN_USE": gpio.Pin 19 --input
    expect-error "UNSUPPORTED": protocol.set-power true
    expect-error "INVALID_ARGUMENT": protocol.read-bits 65
    expect-error "INVALID_ARGUMENT": protocol.write-bits 0 -1
    expect-equals 0 (protocol.read-bits 0)
    protocol.write-bits 0 0
    protocol.write #[]
    expect-equals #[] (protocol.read 0)
    10.repeat:
      expect-equals false protocol.reset
      expect-equals 255 protocol.read-byte
      protocol.write-bits 0xa55a 16
    // Expire during a sequence of hardware operations, then reuse the same
    // controller. A stale completion must not satisfy the next operation.
    10.repeat:
      expect-error "DEADLINE_EXCEEDED":
        with-timeout --us=200:
          while true: protocol.reset
      expect-equals false protocol.reset
      expect-equals 255 protocol.read-byte
  finally:
    protocol.close
  protocol.close
  expect-error "CLOSED": protocol.reset
  expect-error "CLOSED": protocol.read-byte
  pin := gpio.Pin 19 --input
  pin.close
  reopened := HardwareProtocol 19 --pull-up
  reopened.close
  print "Hardware controller ownership, cleanup and API contract PASS"

expect-error expected/string [block]:
  error := catch: block.call
  expect-equals expected error
