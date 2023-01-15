// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import one_wire show *
import expect show *
import monitor

main:
  test_search
  test_verify

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
    TestDevice 0x0000_0000_0000_0001,
    TestDevice 0x5100_0000_FF2A_5A28,
    TestDevice 0x5100_0001_FF2A_5A28,
  ]
  protocol := TestProtocol devices

  bus := Bus.protocol protocol

  bus.do: print "$(%016x it)"


test_verify:
