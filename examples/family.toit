// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import one_wire
import one_wire.family as one_wire

DATA_PIN ::= 32

main:
  bus := one_wire.Bus (gpio.Pin 32)
  print "Listing all devices on bus:"
  bus.do:
    family_id := one_wire.family_id --device_id=it
    print "  $(%x it): $(one_wire.family_to_string family_id)"

  print "Listing only ds18b20 devices on bus:"
  // Only list ds18b20 devices.
  bus.do --family=one_wire.FAMILY_DS18B20:
    print "  $(%x it)"

  print "Demonstrating how to skip families."
  // Skip families.
  bus.do:
    family_id := one_wire.family_id --device_id=it
    print "  Got called with id: $(%x it) - $(one_wire.family_to_string family_id)"
    if family_id == one_wire.FAMILY_DS18B20:
      print "    Skipping remaining devices of this family."
      continue.do one_wire.Bus.SKIP_FAMILY
