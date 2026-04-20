# cmake/toolchains/RaspberryPi2.cmake
#
# Toolchain для Raspberry Pi 2 Model B (v1.0 / v1.1)
# SoC:  BCM2836
# CPU:  Cortex-A7 × 4 (ARMv7-A, NEON + VFPv4, hard-float)
# OS:   Raspberry Pi OS Lite 32-bit
#
# Пакети Ubuntu: gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
#
# Використання:
#   cmake -B build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/RaspberryPi2.cmake \
#     [-DRPI_SYSROOT=/path/to/sysroot]

cmake_minimum_required(VERSION 3.28)

set(CMAKE_SYSTEM_NAME      Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(RPI2_TOOLCHAIN_PREFIX "arm-linux-gnueabihf"
    CACHE STRING "Префікс крос-компілятора для Raspberry Pi 2")

set(_TOOLCHAIN_PREFIX_VAR RPI2_TOOLCHAIN_PREFIX)
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
cross_toolchain_find_compiler(
    "${RPI2_TOOLCHAIN_PREFIX}"
    "gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf")

# --- CPU-специфічні прапори -----------------------------------------------
# -mcpu=cortex-a7       — вибір ядра (включає відповідний -march/-mtune)
# -mfpu=neon-vfpv4      — NEON + VFPv4
# -mfloat-abi=hard      — hard-float ABI
# -mthumb               — Thumb-2 ISA (менший код, достатня швидкість)
set(_RPI2_CPU_FLAGS
    "-mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -mthumb")

set(CMAKE_C_FLAGS_INIT   "${_RPI2_CPU_FLAGS}" CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "${_RPI2_CPU_FLAGS}" CACHE INTERNAL "")

# --- Sysroot ---------------------------------------------------------------
set(RPI_SYSROOT "" CACHE PATH
    "Шлях до sysroot Raspberry Pi (порожньо = збірка без sysroot)")

if(RPI_SYSROOT)
    if(NOT IS_DIRECTORY "${RPI_SYSROOT}")
        message(FATAL_ERROR
            "[Toolchain] RPI_SYSROOT не існує: '${RPI_SYSROOT}'")
    endif()
    set(CMAKE_SYSROOT        "${RPI_SYSROOT}")
    set(CMAKE_FIND_ROOT_PATH "${RPI_SYSROOT}")
    cross_toolchain_setup_sysroot()
else()
    if(CMAKE_CROSSCOMPILING)
        message(FATAL_ERROR
            "[RaspberryPi2] RPI_SYSROOT не задано. "
            "Для крос-компіляції задайте -DRPI_SYSROOT=<path>")
    endif()
    cross_toolchain_no_sysroot()
endif()
