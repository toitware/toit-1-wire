# 1-wire

Implementation of the 1-Wire protocol.

This package is primarily useful for other drivers so they can communicate with sensors.
For example the [ds18b20](https://github.com/toitware/toit-ds18b20) driver uses this
package.

## Implementation

In order to achieve the required precise timings, the implementation offloads the
signal generation and interpretation to the RMT (remote control) module of the ESP32.

It uses 2 of the RMT channels (one for receiving, one for sending).

## References

[datasheet](https://www.ti.com/lit/an/spma057c/spma057c.pdf)
