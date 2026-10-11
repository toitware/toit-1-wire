// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can
// be found in the LICENSE file.

import monitor show Mutex ResourceState_
import .one-wire show Bus Protocol

/**
A standard-speed 1-wire protocol using a dedicated hardware controller.

Currently supported on EC618. Pins use the SDK's native numbering: physical
  PAD numbers on EC618. Use $is-supported to check whether the requested pin
  has a supported route. Controller or pin ownership errors are not treated
  as a reason to fall back to another backend.

Construct a bus with `Bus.protocol (HardwareProtocol pin --pull-up)`.
  The default $Bus constructor continues to select the ESP32 RMT backend.

This backend does not yet support strong power delivery. Requests to enable
  it fail explicitly; externally powered devices can use ordinary transfers.
*/
class HardwareProtocol implements Protocol:
  static resource-group_ ::= hardware-init_
  static DONE_ ::= 1
  static RESET_ ::= 0
  static WRITE_ ::= 1
  static READ_ ::= 2

  resource_/ByteArray? := null
  state_/ResourceState_? := null
  mutex_/Mutex ::= Mutex
  timeout-ms_/int

  /**
  Whether a dedicated controller can use $pin.

  This checks routing support, not current pin/controller availability.
  Requires an SDK that knows the 1-wire primitives, even on platforms that
    do not implement them.
  */
  static is-supported pin/int -> bool:
    result := 0
    error := catch: result = hardware-capabilities_ pin
    if error == "PRIMITIVE_LOOKUP_FAILED": return false
    if error: throw error
    return result & 1 != 0

  /**
  Constructs a hardware protocol on $pin.

  Reserves the pin and its controller until $close. The $pull-up enables the
    pin's internal pull-up; use an external resistor when required by the bus
    capacitance and device timing.

  The $timeout-ms bounds each native reset or transfer of at most eight bits.
    An earlier caller deadline also applies. Cancellation aborts the native
    operation before another task can use the controller.
  */
  constructor pin/int --pull-up/bool=false --timeout-ms/int=100:
    if timeout-ms <= 0: throw "INVALID_ARGUMENT"
    timeout-ms_ = timeout-ms
    if not is-supported pin: throw "UNSUPPORTED"
    resource := hardware-create_ resource-group_ pin pull-up
    resource_ = resource
    initialized := false
    try:
      state_ = ResourceState_ resource-group_ resource
      add-finalizer this:: close
      initialized = true
    finally:
      if not initialized:
        critical-do --no-respect-deadline:
          if state_: state_.dispose
          hardware-close_ resource-group_ resource
          resource_ = null

  /** Whether this protocol is closed. */
  is-closed -> bool:
    return resource_ == null

  /** Closes this protocol and releases its controller and pin. */
  close -> none:
    mutex_.do:
      critical-do --no-respect-deadline:
        if not resource_: return
        hardware-abort_ resource_
        state_.dispose
        hardware-close_ resource-group_ resource_
        resource_ = null
        remove-finalizer this

  /**
  Checks a power-delivery request.

  This backend supports ordinary open-drain transfers only. Enabling strong
    power delivery throws `UNSUPPORTED` before any transfer starts.
  */
  set-power new-value/bool -> none:
    if is-closed: throw "CLOSED"
    if new-value: throw "UNSUPPORTED"

  /** Writes the low $count bits of $value, least-significant bit first. */
  write-bits value/int count/int -> none:
    if not 0 <= count <= 64: throw "INVALID_ARGUMENT"
    mutex_.do:
      if is-closed: throw "CLOSED"
      offset := 0
      while offset < count:
        n := min 8 (count - offset)
        perform_ WRITE_ ((value >> offset) & 0xff) n
        offset += n

  /** Writes the low eight bits of $value. */
  write-byte value/int -> none:
    write-bits value 8

  /** Writes $bytes in order. */
  write bytes/ByteArray -> none:
    mutex_.do:
      if is-closed: throw "CLOSED"
      bytes.do: perform_ WRITE_ it 8

  /** Reads between zero and 64 bits, least-significant bit first. */
  read-bits count/int -> int:
    if not 0 <= count <= 64: throw "INVALID_ARGUMENT"
    return mutex_.do:
      if is-closed: throw "CLOSED"
      result := 0
      offset := 0
      while offset < count:
        n := min 8 (count - offset)
        result |= (perform_ READ_ 0 n) << offset
        offset += n
      result

  /** Reads one byte. */
  read-byte -> int:
    return read-bits 8

  /** Reads $count bytes. */
  read count/int -> ByteArray:
    if count < 0: throw "INVALID_ARGUMENT"
    return mutex_.do:
      if is-closed: throw "CLOSED"
      ByteArray count: perform_ READ_ 0 8

  /** Resets the bus and reports whether a device sent a presence pulse. */
  reset -> bool:
    return mutex_.do:
      if is-closed: throw "CLOSED"
      (perform_ RESET_ 0 0) != 0

  // Called with mutex_ held. Even a failed start must leave no completion
  // state that could satisfy a subsequent operation's wait.
  perform_ operation/int value/int count/int -> int:
    finished := false
    try:
      return with-timeout --ms=timeout-ms_:
        state_.clear-state DONE_
        hardware-start_ resource_ operation value count
        state_.wait-for-state DONE_
        result := hardware-finish_ resource_
        finished = true
        result
    finally:
      if not finished:
        critical-do --no-respect-deadline:
          hardware-abort_ resource_
          state_.clear-state DONE_

hardware-capabilities_ pin/int -> int:
  #primitive.one_wire.capabilities

hardware-init_ -> ByteArray:
  #primitive.one_wire.init

hardware-create_ group/ByteArray pin/int pull-up/bool -> ByteArray:
  #primitive.one_wire.create

hardware-close_ group/ByteArray resource/ByteArray -> none:
  #primitive.one_wire.close

hardware-start_ resource/ByteArray operation/int value/int count/int -> none:
  #primitive.one_wire.start

hardware-finish_ resource/ByteArray -> int:
  #primitive.one_wire.finish

hardware-abort_ resource/ByteArray -> none:
  #primitive.one_wire.abort
