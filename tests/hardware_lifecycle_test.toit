// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the TESTS_LICENSE file.

import expect show *
import gpio
import monitor
import system.containers
import one-wire show Bus
import one-wire.hardware show HardwareProtocol

// Requires one externally powered DS18B20 on EC618 PAD19.
// Keep raw resources rooted without a package finalizer: container teardown
// must release them even if the application never closes or collects them.
raw-group/ByteArray? := null
raw-bus/ByteArray? := null

expect-error expected/string [block]:
  error := catch: block.call
  expect-equals expected error

main arguments:
  if arguments is Map:
    child arguments
    return
  if not HardwareProtocol.is-supported 19:
    print "1WIRE container lifecycle requires EC618 hardware; skipped"
    return
  with-timeout --ms=30_000:
    run-lifecycle

run-lifecycle:
  id := read-id
  // Verify exclusivity across containers, not just across objects in one heap.
  owner := HardwareProtocol 19 --pull-up
  try:
    contender := containers.start containers.current {"mode": "contend"}
    try:
      expect-equals 0 (with-timeout --ms=3000: contender.wait)
    finally:
      if not contender.is-closed: contender.stop
  finally:
    owner.close
  expect-equals id read-id
  print "1WIRE cross-container controller and pad exclusivity PASS"

  ["exit-idle", "exit-pending", "stop-idle", "stop-pending"].do: |mode/string|
    10.repeat: |iteration|
      ready := monitor.Latch
      instance := containers.start containers.current {"mode": mode}
          --on-event=:: |event/int value|
            expect-equals containers.Container.EVENT-BACKGROUND-STATE-CHANGE event
            expect-equals true value
            ready.set true
      try:
        if mode.starts-with "stop":
          with-timeout --ms=3000: ready.get
          expect-error "ALREADY_IN_USE": HardwareProtocol 19
          expect-error "ALREADY_IN_USE": gpio.Pin 19 --input
          with-timeout --ms=3000: instance.stop
        else:
          expect-equals 0 (with-timeout --ms=3000: instance.wait)
      finally:
        if not instance.is-closed: instance.stop
      // No retry or delay: reclamation must be complete when wait/stop returns.
      pin := gpio.Pin 19 --input
      pin.close
      expect-equals id read-id
    print "1WIRE $mode: 10 container teardown/reacquisition cycles PASS"
  print "1WIRE multi-container lifecycle PASS"

read-id -> int:
  bus := Bus.protocol (HardwareProtocol 19 --pull-up)
  try:
    expect-equals true bus.reset
    id := bus.read-device-id
    expect-equals 0x28 (id & 0xff)
    expect-equals ((id >> 56) & 0xff) (Bus.crc8 id)
    expect-equals true (bus.ping id)
    return id
  finally:
    bus.close

child arguments/Map:
  mode/string := arguments["mode"]
  if mode == "contend":
    expect-error "ALREADY_IN_USE": HardwareProtocol 19
    expect-error "ALREADY_IN_USE": HardwareProtocol 17
    expect-error "ALREADY_IN_USE": gpio.Pin 19 --input
    return
  raw-group = native-init
  raw-bus = native-create raw-group 19 true
  if mode.ends-with "pending":
    // Never call finish/abort: leave native ownership and possibly a queued
    // completion behind, bypassing the package's cancellation cleanup.
    native-start raw-bus 0 0 0
  if mode.starts-with "stop":
    containers.notify-background-state-changed true
    sleep --ms=60_000
  // No close and no finally: the native resource group must reclaim both.

native-init -> ByteArray:
  #primitive.one_wire.init

native-create group/ByteArray pin/int pull-up/bool -> ByteArray:
  #primitive.one_wire.create

native-start resource/ByteArray operation/int value/int count/int -> none:
  #primitive.one_wire.start
