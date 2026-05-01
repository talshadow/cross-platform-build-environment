# cmake/toolchains/RaspberryPi3.cmake
#
# Toolchain для Raspberry Pi 3 Model B/B+ та Zero 2 W
# SoC:  BCM2837 / BCM2837B0
# CPU:  Cortex-A53 × 4 (ARMv8-A, 64-bit)
# OS:   Raspberry Pi OS 64-bit (або Ubuntu Server 22.04 arm64)
#
# Для 64-bit OS (рекомендовано):
#   Пакети: gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
#
# Якщо використовується 32-bit OS — застосуйте RaspberryPi2.cmake
# з прапорами cortex-a53 (замість cortex-a7).
#
# Використання:
#   cmake -B build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/RaspberryPi3.cmake \
#     [-DRPI_SYSROOT=/path/to/sysroot]

cmake_minimum_required(VERSION 3.28)

set(CMAKE_SYSTEM_NAME      Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(RPI3_TOOLCHAIN_PREFIX "aarch64-linux-gnu"
    CACHE STRING "Префікс крос-компілятора для Raspberry Pi 3")

set(_TOOLCHAIN_PREFIX_VAR RPI3_TOOLCHAIN_PREFIX)
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
cross_toolchain_find_compiler(
    "${RPI3_TOOLCHAIN_PREFIX}"
    "gcc-aarch64-linux-gnu g++-aarch64-linux-gnu")

# --- CPU-специфічні прапори -----------------------------------------------
# -mcpu=cortex-a53  — Cortex-A53, включає ARMv8-A + CRC
# Без -mfloat-abi: у AArch64 завжди використовується hard-float
set(_RPI3_CPU_FLAGS "-mcpu=cortex-a53")

set(CMAKE_C_FLAGS_INIT   "${_RPI3_CPU_FLAGS} -std=gnu11" CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "${_RPI3_CPU_FLAGS} -std=c++20" CACHE INTERNAL "")

# --- Sysroot ---------------------------------------------------------------
set(RPI_SYSROOT "" CACHE PATH
    "Шлях до sysroot Raspberry Pi (порожньо = збірка без sysroot)")

cross_toolchain_apply_sysroot(RPI_SYSROOT)
