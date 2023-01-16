// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Source: https://www.analog.com/en/technical-articles/1wire-software-resource-guide-device-description.html
// and https://owfs.org/index_php_page_family-code-list.html

/**
1-Wire net address (registration number) only.

Also includes DS1990R, DS2401, and DS2411.
*/
FAMILY_DS1990A ::= 0x01

/** Multikey iButton, 1152-bit secure memory. */
FAMILY_DS1991 ::= 0x02

/**
4Kb NV RAM memory and clock, timer, alarms.

Also includes DS2404.
*/
FAMILY_DS1994 ::= 0x04

/** Single addressable switch. */
FAMILY_DS2405 ::= 0x05

/** 4Kb NV RAM memory. */
FAMILY_DS1993 ::= 0x06

/** 1Kb NV RAM memory. */
FAMILY_DS1992 ::= 0x08

/**
1Kb EPROM memory.

Also includes DS2502.
*/
FAMILY_DS1982 ::= 0x09

/** 16Kb NV RAM memory. */
FAMILY_DS1995 ::= 0x0A

/**
16Kb EPROM memory.

Also includes DS2505.
*/
FAMILY_DS1985 ::= 0x0B

/** 64Kb NV RAM memory. */
FAMILY_DS1996 ::= 0x0C

/**
64Kb EPROM memory.

Also includes DS2506.
*/
FAMILY_DS1986 ::= 0x0F

/** Temperature with alarm trips. */
FAMILY_DS1920 ::= 0x10

/**
1Kb EPROM memory, 2-channel addressable switch.

Also includes DS2407.
*/
FAMILY_DS2406 ::= 0x12

/**
256-bit EEPROM memory and 64-bit OTP register.

Also includes DS2430A.
*/
FAMILY_DS1971 ::= 0x14

/**
Cryptographic iButton.

Also includes DS1957 (Java-Powered).
*/
FAMILY_DS1954 ::= 0x16

/** 1024-bit monetary iButton with SHA-1 function. */
FAMILY_DS1962 ::= 0x18

/** 4096-bit monetary iButton with SHA-1 function. */
FAMILY_DS1963 ::= 0x1A

/** Battery ID/monitor. */
FAMILY_DS2436 ::= 0x1B

/** 4096-bit EEPROM memory, 2-channel addressable switch. */
FAMILY_DS28E04_100 ::= 0x1C

/** 4Kb NV RAM memory with external counters. */
FAMILY_DS2423 ::= 0x1D

/** Smart battery monitor. */
FAMILY_DS2437 ::= 0x1E

/** 2-channel addressable coupler for sub-netting. */
FAMILY_DS2409 ::= 0x1F

/** 4-channel A/D converter (ADC). */
FAMILY_DS2450 ::= 0x20

/**
Thermochron® temperature logger.

Also includes DS1921H, and DS1921Z.
*/
FAMILY_DS1921G ::= 0x21

/** iButton temperature logger with 8kB datalog memory. */
FAMILY_DS1922 ::= 0x22

/**
4Kb EEPROM memory.

Also includes DS2433.
*/
FAMILY_DS1973 ::= 0x23

/**
Real-time clock (RTC).

Also includes DS2415.
*/
FAMILY_DS1904 ::= 0x24

/** Smart battery monitor. */
FAMILY_DS2438 ::= 0x26

/** RTC with interrupt. */
FAMILY_DS2417 ::= 0x27

/** Programmable resolution thermometer. */
FAMILY_DS18B20 ::= 0x28

/** 4-channel addressable switch. */
FAMILY_DS2408 ::= 0x29

/** 1-channel digital potentiometer. */
FAMILY_DS2890 ::= 0x2C

/**
1024-bit EEPROM memory.

Also includes DS2431.
*/
FAMILY_DS1972 ::= 0x2D

/** Battery management. */
FAMILY_DS2770 ::= 0x2E

/** High-precision Li+ battery monitor. */
FAMILY_DS2760 ::= 0x30

/** Single-cell rechargeable lithium protection. */
FAMILY_DS2720 ::= 0x31

/** Battery fuel gauge. */
FAMILY_DS2780 ::= 0x32

/**
1128-bit iButton with SHA-1 engine.

Also includes DS2432.
*/
FAMILY_DS1961S ::= 0x33

/** Battery pack authentication. */
FAMILY_DS2703 ::= 0x34

/** High-accuracy battery fuel gauge. */
FAMILY_DS2755 ::= 0x35

/** High-precision coulomb counter. */
FAMILY_DS2740 ::= 0x36

/** Password-protected 32KB (bytes) EEPROM. */
FAMILY_DS1977 ::= 0x37

/** 2-channel addressable switch. */
FAMILY_DS2413 ::= 0x3A

/**
Programmable resolution thermometer.

Also includes MAX31826 (temperature sensor with 1Kb lockable EEPROM).
*/
FAMILY_DS1825 ::= 0x3B

/** 1-cell or 2-cell battery fuel gauge. */
FAMILY_DS2781 ::= 0x3D

/**
High-capacity Thermochron (temperature) and Hygrochron™ (humidity) loggers.

Also includes DS1922T, DS1923, and DS2422
*/
FAMILY_DS1922L ::= 0x41

/** Programmable resolution digital thermometer with sequenced detection and PIO. */
FAMILY_DS28EA00 ::= 0x42

/** 20Kb 1-Wire EEPROM. */
FAMILY_DS28EC20 ::= 0x43

/** SHA-1 authenticator. */
FAMILY_DS28E10 ::= 0x44

/** Multichemistry battery fuel gauge. */
FAMILY_DS2751 ::= 0x51

/** Environmental sensor. */
FAMILY_EDS00XX ::= 0x7E

/** USB ID. */
FAMILY_DS2490 ::= 0x81

/** Multi iButton with three 384-bit fields of password-protected RAM. */
FAMILY_DS1425 ::= 0x82

/** UniqueWare™ iButton with 1024 bits EPROM. */
FAMILY_DS1982U ::= 0x89

/** UniqueWare™ iButton with 16Kb EPROM. */
FAMILY_DS1985U ::= 0x8B

/** UniqueWare™ iButton with 64Kb EPROM. */
FAMILY_DS1986U ::= 0x8F

/** Shaft rotation sensor. */
FAMILY_MRS001 ::= 0xA0

/** Vibration sensor. */
FAMILY_MVM001 ::= 0xA1

/** AC current sensor. */
FAMILY_MCMC001 ::= 0xA2

/** Infrared temperature sensor. */
FAMILY_MTS017 ::= 0xA6

/** Thermocouple converter. */
FAMILY_MTC001 ::= 0xB1

/** Analog input module. */
FAMILY_MAM001 ::= 0xB2

/** Thermocouple converter. */
FAMILY_MTC002 ::= 0xB3

/** UV index sensor. */
FAMILY_UVI_01 ::= 0xEE

/** Moisture hub. */
FAMILY_MOISTURE_HUB ::= 0xEF

/**
Programmable microprocessor.

Also includes BAE0911.
*/
FAMILY_BAE0910 ::= 0xFC

/** LCD. */
FAMILY_LCD ::= 0xFF


family_id --device_id/int -> int:
    return device_id & 0xFF

family_to_string family_id/int -> string:
  if family_id == FAMILY_DS1990A:
    return "1-Wire net address (registration number) only. DS1990A, DS1990R, DS2401, DS2411."
  if family_id == FAMILY_DS1991:
    return "Multikey iButton, 1152-bit secure memory. DS1991."
  if family_id == FAMILY_DS1994:
    return "4Kb NV RAM memory and clock, timer, alarms. DS1994, DS2404."
  if family_id == FAMILY_DS2405:
    return "Single addressable switch. DS2405."
  if family_id == FAMILY_DS1993:
    return "4Kb NV RAM memory. DS1993."
  if family_id == FAMILY_DS1992:
    return "1Kb NV RAM memory. DS1992."
  if family_id == FAMILY_DS1982:
    return "1Kb EPROM memory. DS1982, DS2502."
  if family_id == FAMILY_DS1995:
    return "16Kb NV RAM memory. DS1995."
  if family_id == FAMILY_DS1985:
    return "16Kb EPROM memory. DS1985, DS2505."
  if family_id == FAMILY_DS1996:
    return "64Kb NV RAM memory. DS1996."
  if family_id == FAMILY_DS1986:
    return "64Kb EPROM memory. DS1986, DS2506."
  if family_id == FAMILY_DS1920:
    return "Temperature with alarm trips. DS1920."
  if family_id == FAMILY_DS2406:
    return "1Kb EPROM memory, 2-channel addressable switch. DS2406, DS2407."
  if family_id == FAMILY_DS1971:
    return "256-bit EEPROM memory and 64-bit OTP register. DS1971, DS2430A."
  if family_id == FAMILY_DS1954:
    return "Cryptographic iButton. DS1954, DS1957 (Java-Powered)."
  if family_id == FAMILY_DS1962:
    return "1024-bit monetary iButton with SHA-1 function. DS1962."
  if family_id == FAMILY_DS1963:
    return "4096-bit monetary iButton with SHA-1 function. DS1963."
  if family_id == FAMILY_DS2436:
    return "Battery ID/monitor. DS2436."
  if family_id == FAMILY_DS28E04_100:
    return "4096-bit EEPROM memory, 2-channel addressable switch. DS28E04-100."
  if family_id == FAMILY_DS2423:
    return "4Kb NV RAM memory with external counters. DS2423."
  if family_id == FAMILY_DS2437:
    return "Smart battery monitor. DS2437."
  if family_id == FAMILY_DS2409:
    return "2-channel addressable coupler for sub-netting. DS2409."
  if family_id == FAMILY_DS2450:
    return "4-channel A/D converter (ADC). DS2450."
  if family_id == FAMILY_DS1921G:
    return "Thermochron® temperature logger. DS1921G, DS1921H, DS1921Z."
  if family_id == FAMILY_DS1922:
    return "iButton temperature logger with 8kB datalog memory. DS1922."
  if family_id == FAMILY_DS1973:
    return "4Kb EEPROM memory. DS1973, DS2433."
  if family_id == FAMILY_DS1904:
    return "Real-time clock (RTC). DS1904, DS2415."
  if family_id == FAMILY_DS2438:
    return "Smart battery monitor. DS2438."
  if family_id == FAMILY_DS2417:
    return "RTC with interrupt. DS2417."
  if family_id == FAMILY_DS18B20:
    return "Programmable resolution thermometer. DS18B20."
  if family_id == FAMILY_DS2408:
    return "8-channel addressable switch. DS2408."
  if family_id == FAMILY_DS2890:
    return "1-channel digital potentiometer. DS2890."
  if family_id == FAMILY_DS1972:
    return "1024-bit, 1-Wire EEPROM. DS1972, DS2431."
  if family_id == FAMILY_DS2770:
    return "Battery management. DS2770."
  if family_id == FAMILY_DS2760:
    return "High-precision Li+ battery monitor. DS2760."
  if family_id == FAMILY_DS2720:
    return "Single-cell rechargeable lithium protection. DS2720."
  if family_id == FAMILY_DS2780:
    return "Battery fuel gauge. DS2780."
  if family_id == FAMILY_DS1961S:
    return "1128-bit iButton with SHA-1 engine. DS1961s, DS2432."
  if family_id == FAMILY_DS2703:
    return "Battery pack authentication. DS2703."
  if family_id == FAMILY_DS2755:
    return "High-accuracy battery fuel gauge. DS2755."
  if family_id == FAMILY_DS2740:
    return "High-precision coulomb counter. DS2740."
  if family_id == FAMILY_DS1977:
    return "Password-protected 32KB (bytes) EEPROM. DS1977."
  if family_id == FAMILY_DS2413:
    return "2-channel addressable switch. DS2413."
  if family_id == FAMILY_DS1825:
    return "Programmable resolution thermometer. DS1825, MAX31826."
  if family_id == FAMILY_DS2781:
    return "1-cell or 2-cell battery fuel gauge. DS2781."
  if family_id == FAMILY_DS1922L:
    return "High-capacity Thermochron (temperature) and Hygrochron™ (humidity) loggers. DS1922L, DS1922T, DS1923, DS2422."
  if family_id == FAMILY_DS28EA00:
    return "Programmable resolution digital thermometer with sequenced detection and PIO. DS28EA00."
  if family_id == FAMILY_DS28EC20:
    return "20Kb 1-Wire EEPROM. DS28EC20."
  if family_id == FAMILY_DS28E10:
    return "SHA-1 authenticator. DS28E10."
  if family_id == FAMILY_DS2751:
    return "Multichemistry battery fuel gauge. DS2751."
  if family_id == FAMILY_EDS00XX:
    return "Environmental sensor. EDS00xx."
  if family_id == FAMILY_DS2490:
    return "USB ID. DS2490."
  if family_id == FAMILY_DS1425:
    return "Multi iButton with three 384-bit fields of password-protected RAM. DS1425."
  if family_id == FAMILY_DS1982U:
    return "UniqueWare™ iButton with 1024 bits EPROM. DS1982U."
  if family_id == FAMILY_DS1985U:
    return "UniqueWare™ iButton with 16Kb EPROM. DS1985U."
  if family_id == FAMILY_DS1986U:
    return "UniqueWare™ iButton with 64Kb EPROM. DS1986U."
  if family_id == FAMILY_MRS001:
    return "Shaft rotation sensor. mRS001."
  if family_id == FAMILY_MVM001:
    return "Vibration sensor. mVM001."
  if family_id == FAMILY_MCMC001:
    return "AC current sensor. mCMC001."
  if family_id == FAMILY_MTS017:
    return "Infrared temperature sensor. mTS017."
  if family_id == FAMILY_MTC001:
    return "Thermocouple converter. mTC001."
  if family_id == FAMILY_MAM001:
    return "Analog input module. mAM001."
  if family_id == FAMILY_MTC002:
    return "Thermocouple converter. mTC002."
  if family_id == FAMILY_UVI_01:
    return "UV index sensor. UVI-01."
  if family_id == FAMILY_MOISTURE_HUB:
    return "Moisture hub."
  if family_id == FAMILY_BAE0910:
    return "Programmable microprocessor. BAE0910, BAE0911."
  if family_id == FAMILY_LCD:
    return "LCD."
  return "Unknown family id: $(%x family_id)"
