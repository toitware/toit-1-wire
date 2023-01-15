// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import one_wire show *
import expect show *
import monitor

main:
  test_search
  test_ping
  test_id_crc

class TestDevice:
  static STATE_IDLE ::= 0
  static STATE_RESET ::= 1
  static STATE_SEARCH_BIT ::= 2
  static STATE_SEARCH_COMPLEMENT ::= 3
  static STATE_SEARCH_WAIT_FOR_DECISION ::= 4
  static STATE_SEARCH_DROP_OUT ::= 5

  static COMMAND_SEARCH ::= 0xF0
  static COMMAND_SEARCH_ALARM ::= 0xEC

  id/int
  state/int := STATE_IDLE
  has_alarm/bool := false
  search_bit/int := -1

  constructor .id:

  write_byte byte/int:
    if state != STATE_RESET: throw "UNIMPLEMENTED"
    if byte == COMMAND_SEARCH:
      reset_search_
    else if byte == COMMAND_SEARCH_ALARM:
      if has_alarm:
        reset_search_
      else:
        state = STATE_IDLE
    else:
      throw "UNIMPLEMENTED"

  write_bit bit/int:
    if state == STATE_SEARCH_DROP_OUT: return
    if state != STATE_SEARCH_WAIT_FOR_DECISION:
      throw "UNIMPLEMENTED"
    my_bit := (id >> search_bit) & 1
    if bit != my_bit:
      state = STATE_SEARCH_DROP_OUT
      return
    search_bit++
    state = STATE_SEARCH_BIT

  read_bit -> int?:
    if state == STATE_SEARCH_DROP_OUT: return null
    if state == STATE_SEARCH_BIT:
      state = STATE_SEARCH_COMPLEMENT
      assert: search_bit >= 0
      return (id >> search_bit) & 1
    if state == STATE_SEARCH_COMPLEMENT:
      assert: search_bit >= 0
      state = STATE_SEARCH_WAIT_FOR_DECISION
      return ((id >> search_bit) & 1) ^ 1
    throw "UNIMPLEMENTED"

  reset_search_:
    state = STATE_SEARCH_BIT
    search_bit = 0

  reset:
    state = STATE_RESET

class TestProtocol implements Protocol:
  devices/List

  constructor .devices:

  is_closed/bool := false
  close: is_closed = true

  write_bits value/int count/int -> none:
    count.repeat:
      bit := value & 1
      devices.do: it.write_bit bit
      value >>= 1

  write_byte byte/int -> none:
    devices.do: it.write_byte byte

  write bytes/ByteArray -> none:
    bytes.do: write_byte it

  read_byte -> int:
    throw "UNIMPLEMENTED"

  read_bit -> int:
    bits := devices.map: it.read_bit
    bits.filter --in_place: it != null
    if bits.is_empty: return 1
    return bits.reduce: | a b | a & b

  read_bits count/int -> int:
    result := 0
    count.repeat:
      result |= read_bit << it
    return result

  read count/int -> ByteArray:
    throw "UNIMPLEMENTED"

  reset:
    devices.do: it.reset
    return not devices.is_empty

test_search:
  devices := [
    // TODO(florian): fix CRC of first and third device.
    TestDevice 0x3D00_0000_0000_0001,
    TestDevice 0x5100_0000_FF2A_5A28,
    TestDevice 0xFA00_0001_FF2A_5A28,
  ]
  protocol := TestProtocol devices

  bus := Bus.protocol protocol

  found := {}
  bus.do:
    found.add it

  expect_equals 3 found.size

  devices.do: expect (found.contains it.id)

  // Search for families.
  found = {}
  bus.do --family=0x01:
    found.add it

  expect_equals 1 found.size
  expect (found.contains 0x3D00_0000_0000_0001)

  // Search for 0x28 family.
  found = {}
  bus.do --family=0x28:
    found.add it

  expect_equals 2 found.size
  expect (found.contains 0x5100_0000_FF2A_5A28)
  expect (found.contains 0xFA00_0001_FF2A_5A28)

  // Skip family.
  found = {}

  bus.do:
    found.add it
    if it & 0xFF == 0x28: continue.do Bus.SKIP_FAMILY

  // Because we skipped the remaining entries of the 0x28 family, we should
  // only find the first entry.
  expect_equals 2 found.size
  expect (found.contains 0x3D00_0000_0000_0001)
  // The one-wire bus goes from the LSB to the MSB, trying '0'
  // bits first.
  expect (found.contains 0x5100_0000_FF2A_5A28)

test_ping:
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

  expect_not (bus.ping 0x3D00_0000_0000_0000)
  expect_not (bus.ping 0x5100_0000_FF2A_5A29)
  expect_not (bus.ping 0xFA00_0001_FF2A_5A29)

test_id_crc:
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
    expect_equals (it >>> 56) crc
