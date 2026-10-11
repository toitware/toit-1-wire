# 1-wire

Implementation of the 1-Wire protocol.

This package is primarily useful for other drivers so they can communicate with sensors.
For example the [ds18b20](https://github.com/toitware/toit-ds18b20) driver uses this
package.

## Implementation

In order to achieve the required precise timings, the implementation offloads the
signal generation and interpretation to the RMT (remote control) module of the ESP32.

It uses 2 of the RMT channels (one for receiving, one for sending).

### Dedicated hardware controller (development)

The optional `one-wire.hardware` import provides `HardwareProtocol`, backed by
native SDK primitives. The EC618 implementation uses interrupts for reset and bit/byte
transfers; ROM search and CRC remain in the shared `Bus` implementation.

```toit
import one-wire show Bus
import one-wire.hardware show HardwareProtocol

main:
  bus := Bus.protocol (HardwareProtocol 19 --pull-up)
  try:
    bus.do: print "Device: $it"
  finally:
    bus.close
```

EC618 pin numbers are physical PAD numbers. `HardwareProtocol.is-supported pin`
checks the route; it does not check availability. A supported but occupied pin
or controller reports `ALREADY_IN_USE`. The ordinary `Bus` constructor still
uses RMT, so backend selection is explicit during qualification.

Each native operation has a deadline, and cancellation aborts that operation
before the controller is reused. Strong power delivery is not implemented:
`set-power true` throws `UNSUPPORTED`. Use an externally powered sensor with
this backend.

`tests/hardware_lifecycle_test.toit` runs on an EC618 with one externally
powered DS18B20 on PAD19. It verifies cross-container exclusivity and ten
cycles each of normal exit and forced stop with idle or uncollected native
operations. The child deliberately bypasses package finalizers; after each
teardown the parent immediately reclaims the pin and verifies the sensor ROM
and its CRC. This test requires the firmware container service and skips on
platforms without the hardware backend. The unloaded-line contract test is
separate and requires no sensor on PAD19.

The ordinary `one-wire` import retains the SDK requirement in `package.yaml`
(`^2.0.0-alpha.196`). The optional `one-wire.hardware` import requires the
matching EC618 development SDK that declares the `one_wire` primitives. No
released SDK minimum is claimed for that optional import yet. Older compilers
reject unknown primitives even in unused code; keeping them in a separate
library lets existing ESP32/RMT applications continue to compile. A runtime
capability check alone cannot provide that compiler compatibility.

With a compiler that knows the primitives, `HardwareProtocol.is-supported`
returns false on a platform without the controller. It does not catch pin
ownership errors or silently choose RMT after a hardware failure.

The default test suite covers the shared bus and RMT code on the declared
minimum SDK. To include the optional backend tests with a matching SDK:

```sh
cmake -S . -B build/hardware -DTOIT=/path/to/sdk/bin/toit -DONE_WIRE_HARDWARE_TESTS=ON
cmake --build build/hardware --target check
```

On a host, these tests check backend absence and skip physical sensor checks.
Run the lifecycle test on the EC618 to exercise actual transfers and container
cleanup. Before releasing the optional backend, record the first published SDK
containing its primitives and add that SDK to the test matrix.

## References

[datasheet](https://www.ti.com/lit/an/spma057c/spma057c.pdf)
