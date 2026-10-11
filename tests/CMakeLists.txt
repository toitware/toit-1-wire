# Copyright (C) 2023 Toitware ApS.
# Use of this source code is governed by a Zero-Clause BSD license that can
# be found in the tests/TESTS_LICENSE file.

file(GLOB TESTS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} "*_test.toit" "*-test.toit")

option(ONE_WIRE_HARDWARE_TESTS "Test the optional backend (requires an SDK with one_wire primitives)" OFF)
if(NOT ONE_WIRE_HARDWARE_TESTS)
  list(REMOVE_ITEM TESTS hardware_contract_test.toit hardware_lifecycle_test.toit)
  message(STATUS "Optional hardware backend tests disabled; enable ONE_WIRE_HARDWARE_TESTS with a matching SDK")
endif()

# Add windows exe extension.
set(TOIT "toit${CMAKE_EXECUTABLE_SUFFIX}" CACHE FILEPATH "The executable used to run the tests")
set(TEST_TIMEOUT 40 CACHE STRING "The maximal amount of time each test is allowed to run")
set(SLOW_TEST_TIMEOUT 200 CACHE STRING "The maximal amount of time each slow test is allowed to run")

add_custom_target(
  "install-pkgs"
  COMMAND "${TOIT}" pkg install
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
)

include(ProcessorCount)
ProcessorCount(NUM_CPU)

add_custom_target(
  check
  COMMAND ${CMAKE_CTEST_COMMAND} -j${NUM_CPU} -T test --output-on-failure -C Debug
  USES_TERMINAL
)

foreach(file ${TESTS})
  add_test(
    NAME ${file}
    COMMAND "${TOIT}" "${file}"
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    )
  set_tests_properties(${file} PROPERTIES TIMEOUT ${TEST_TIMEOUT})
endforeach()
