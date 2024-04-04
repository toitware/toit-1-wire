// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import one-wire
import one-wire.family as one-wire

DATA-PIN ::= 32

main:
  bus := one-wire.Bus (gpio.Pin 32)
  print "Listing all devices on bus:"
  bus.do:
    family-id := one-wire.family-id --device-id=it
    print "  $(%x it): $(one-wire.family-to-string family-id)"

  print "Listing only ds18b20 devices on bus:"
  // Only list ds18b20 devices.
  bus.do --family=one-wire.FAMILY-DS18B20:
    print "  $(%x it)"

  print "Demonstrating how to skip families."
  // Skip families.
  bus.do:
    family-id := one-wire.family-id --device-id=it
    print "  Got called with id: $(%x it) - $(one-wire.family-to-string family-id)"
    if family-id == one-wire.FAMILY-DS18B20:
      print "    Skipping remaining devices of this family."
      continue.do one-wire.Bus.SKIP-FAMILY
