# cmake/toolchains/RaspberryPi5.cmake
#
# Toolchain для Raspberry Pi 5
# SoC:  BCM2712
# CPU:  Cortex-A76 × 4 (ARMv8.2-A, 64-bit)
# OS:   Raspberry Pi OS 64-bit / Ubuntu Server 24.04 arm64
#
# Пакети Ubuntu: gcc-13-aarch64-linux-gnu g++-13-aarch64-linux-gnu
#
# Використання:
#   cmake -B build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/RaspberryPi5.cmake \
#     [-DRPI_SYSROOT=/path/to/sysroot]

cmake_minimum_required(VERSION 3.28)

set(CMAKE_SYSTEM_NAME      Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(RPI5_TOOLCHAIN_PREFIX "aarch64-linux-gnu"
    CACHE STRING "Префікс крос-компілятора для Raspberry Pi 5")

set(RPI5_GCC_VERSION "13"
    CACHE STRING "Версія GCC для крос-компіляції RPi 5 (13, 14, ...)")

set(_TOOLCHAIN_PREFIX_VAR RPI5_TOOLCHAIN_PREFIX)
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

cross_toolchain_find_versioned_cross_compiler(
    "${RPI5_TOOLCHAIN_PREFIX}"
    "${RPI5_GCC_VERSION}")

if(NOT _vcc_found)
    message(WARNING
        "[RaspberryPi5] gcc-${RPI5_GCC_VERSION} не знайдено, "
        "використовується неверсований aarch64-linux-gnu-gcc. "
        "Встановіть: sudo apt install gcc-${RPI5_GCC_VERSION}-aarch64-linux-gnu")
    cross_toolchain_find_compiler(
        "${RPI5_TOOLCHAIN_PREFIX}"
        "gcc-${RPI5_GCC_VERSION}-aarch64-linux-gnu g++-${RPI5_GCC_VERSION}-aarch64-linux-gnu")
endif()
unset(_vcc_found)

# --- CPU-специфічні прапори -----------------------------------------------
# -mcpu=cortex-a76  — Cortex-A76 (BCM2712), ARMv8.2-A
# +crc              — апаратний CRC32
# +simd             — Advanced SIMD
# +crypto           — апаратне шифрування (AES, SHA)
# +dotprod          — Dot Product (корисно для ML задач)
# -march=armv8.2-a  — мінімальна ISA (автоматично з cortex-a76,
#                      але явне задання покращує діагностику)
set(_RPI5_CPU_FLAGS "-mcpu=cortex-a76+crc+simd+crypto+dotprod")

set(CMAKE_C_FLAGS_INIT   "${_RPI5_CPU_FLAGS} -std=gnu11"   CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "${_RPI5_CPU_FLAGS} -std=c++20" CACHE INTERNAL "")

# --- Sysroot ---------------------------------------------------------------
set(RPI_SYSROOT "" CACHE PATH
    "Шлях до sysroot Raspberry Pi (порожньо = збірка без sysroot)")

cross_toolchain_apply_sysroot(RPI_SYSROOT)
