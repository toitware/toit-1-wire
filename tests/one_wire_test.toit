// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import one-wire show *
import expect show *
import monitor

main:
  test-search
  test-ping
  test-id-crc

class TestDevice:
  static STATE-IDLE ::= 0
  static STATE-RESET ::= 1
  static STATE-SEARCH-BIT ::= 2
  static STATE-SEARCH-COMPLEMENT ::= 3
  static STATE-SEARCH-WAIT-FOR-DECISION ::= 4
  static STATE-SEARCH-DROP-OUT ::= 5

  static COMMAND-SEARCH ::= 0xF0
  static COMMAND-SEARCH-ALARM ::= 0xEC

  id/int
  state/int := STATE-IDLE
  has-alarm/bool := false
  search-bit/int := -1

  constructor .id:

  write-byte byte/int:
    if state != STATE-RESET: throw "UNIMPLEMENTED"
    if byte == COMMAND-SEARCH:
      reset-search_
    else if byte == COMMAND-SEARCH-ALARM:
      if has-alarm:
        reset-search_
      else:
        state = STATE-SEARCH-DROP-OUT
    else:
      throw "UNIMPLEMENTED"

  write-bit bit/int:
    if state == STATE-SEARCH-DROP-OUT: return
    if state != STATE-SEARCH-WAIT-FOR-DECISION:
      throw "UNIMPLEMENTED"
    my-bit := (id >> search-bit) & 1
    if bit != my-bit:
      state = STATE-SEARCH-DROP-OUT
      return
    search-bit++
    state = STATE-SEARCH-BIT

  read-bit -> int?:
    if state == STATE-SEARCH-DROP-OUT: return null
    if state == STATE-SEARCH-BIT:
      state = STATE-SEARCH-COMPLEMENT
      assert: search-bit >= 0
      return (id >> search-bit) & 1
    if state == STATE-SEARCH-COMPLEMENT:
      assert: search-bit >= 0
      state = STATE-SEARCH-WAIT-FOR-DECISION
      return ((id >> search-bit) & 1) ^ 1
    throw "UNIMPLEMENTED"

  reset-search_:
    state = STATE-SEARCH-BIT
    search-bit = 0

  reset:
    state = STATE-RESET

class TestProtocol implements Protocol:
  devices/List

  constructor .devices:

  is-closed/bool := false
  is-powered/bool := false
  close: is-closed = true

  write-bits value/int count/int -> none:
    count.repeat:
      bit := value & 1
      devices.do: it.write-bit bit
      value >>= 1

  write-byte byte/int -> none:
    devices.do: it.write-byte byte

  write bytes/ByteArray -> none:
    bytes.do: write-byte it

  read-byte -> int:
    throw "UNIMPLEMENTED"

  read-bit -> int:
    expect-not is-powered
    bits := devices.map: it.read-bit
    bits.filter --in-place: it != null
    if bits.is-empty: return 1
    return bits.reduce: | a b | a & b

  read-bits count/int -> int:
    expect-not is-powered
    result := 0
    count.repeat:
      result |= read-bit << it
    return result

  read count/int -> ByteArray:
    expect-not is-powered
    throw "UNIMPLEMENTED"

  reset:
    devices.do: it.reset
    return not devices.is-empty

  set-power power/bool -> none:
    is-powered_ := power

test-search:
  devices := [
    TestDevice 0x3D00_0000_0000_0001,
    TestDevice 0x5100_0000_FF2A_5A28,
    TestDevice 0xFA00_0001_FF2A_5A28,
  ]
  protocol := TestProtocol devices

  bus := Bus.protocol protocol

  found := {}
  bus.do:
    found.add it
  expect-equals 3 found.size
  devices.do: expect (found.contains it.id)

  // None of the devices have an alarm.
  found = {}
  bus.do --alarm-only:
    found.add it
  expect-equals 0 found.size

  // Set an alarm on the second device.
  devices[1].has-alarm = true

  // Now search again.
  found = {}
  bus.do --alarm-only:
    found.add it
  expect-equals 1 found.size
  expect (found.contains 0x5100_0000_FF2A_5A28)

  // Search for families.
  found = {}
  bus.do --family=0x01:
    found.add it

  expect-equals 1 found.size
  expect (found.contains 0x3D00_0000_0000_0001)

  // Search for 0x28 family.
  found = {}
  bus.do --family=0x28:
    found.add it

  expect-equals 2 found.size
  expect (found.contains 0x5100_0000_FF2A_5A28)
  expect (found.contains 0xFA00_0001_FF2A_5A28)

  // Skip family.
  found = {}

  bus.do:
    found.add it
    if it & 0xFF == 0x28: continue.do Bus.SKIP-FAMILY

  // Because we skipped the remaining entries of the 0x28 family, we should
  // only find the first entry.
  expect-equals 2 found.size
  expect (found.contains 0x3D00_0000_0000_0001)
  // The one-wire bus goes from the LSB to the MSB, trying '0'
  // bits first.
  expect (found.contains 0x5100_0000_FF2A_5A28)

test-ping:
  devices := [
    // TODO(florian): fix CRC of first and third device.
    TestDevice 0x3D00_0000_0000_0001,
    TestDevice 0x5100_0000_FF2A_5A28,
    TestDevice 0xFA00_0001_FF2A_5A28,
  ]
  protocol := TestProtocol devices
  bus := Bus.protocol protocol

  devices.do:
    expect (bus.ping it.id)

  expect-not (bus.ping 0x3D00_0000_0000_0000)
  expect-not (bus.ping 0x5100_0000_FF2A_5A29)
  expect-not (bus.ping 0xFA00_0001_FF2A_5A29)

test-id-crc:
  ids := []
  // Id from https://www.analog.com/en/technical-articles/understanding-and-using-cyclic-redundancy-checks-with-maxim-1wire-and-ibutton-products.html
  ids.add 0xA200_0000_01B8_1C02
  // Ids found on the internet:
  ids.add 0xD7AA_13C0_2916_9085
  ids.add 0xA600_0801_9470_1310
  ids.add 0x2E00_0002_8FAD_4928
  // The ids we use in the rest of the tests:
  ids.add 0x3D00_0000_0000_0001
  ids.add 0x5100_0000_FF2A_5A28
  ids.add 0xFA00_0001_FF2A_5A28

  ids.do:
    crc := Bus.crc8 it
    expect-equals (it >>> 56) crc
