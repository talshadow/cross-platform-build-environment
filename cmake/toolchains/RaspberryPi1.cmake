# cmake/toolchains/RaspberryPi1.cmake
#
# Toolchain для Raspberry Pi 1 / Zero / Zero W
# SoC:  BCM2835
# CPU:  ARM1176JZF-S (ARMv6, VFPv2 hard-float)
# OS:   Raspberry Pi OS Lite 32-bit (bullseye/bookworm)
#
# УВАГА: стандартний Ubuntu пакет gcc-arm-linux-gnueabihf
# скомпільований з ARMv7 baseline і НЕ гарантує коректну роботу
# на ARMv6. Для офіційної підтримки ARMv6 використовуйте toolchain
# від Raspberry Pi Foundation:
#   https://github.com/raspberrypi/tools  (GCC 8, 32-bit)
#   https://github.com/rvagg/rpi-newer-crosstools (GCC 10+)
# або збирайте через crosstool-NG.
#
# Використання:
#   cmake -B build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/RaspberryPi1.cmake \
#     [-DRPI_SYSROOT=/path/to/sysroot]
#     [-DRPI1_TOOLCHAIN_PREFIX=arm-linux-gnueabihf]

cmake_minimum_required(VERSION 3.28)

# --- Цільова система -------------------------------------------------------
set(CMAKE_SYSTEM_NAME      Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

# --- Конфігурація тулчейну ------------------------------------------------
set(RPI1_TOOLCHAIN_PREFIX "arm-linux-gnueabihf"
    CACHE STRING "Префікс крос-компілятора для Raspberry Pi 1")

set(_TOOLCHAIN_PREFIX_VAR RPI1_TOOLCHAIN_PREFIX)
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
cross_toolchain_find_compiler(
    "${RPI1_TOOLCHAIN_PREFIX}"
    "gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf")

# --- CPU-специфічні прапори -----------------------------------------------
# -march=armv6zk    — ARMv6 з Thumb + Jazelle (BCM2835)
# -mtune=arm1176jzf-s — оптимізація для конкретного ядра
# -mfpu=vfp         — VFPv2 FPU
# -mfloat-abi=hard  — hard-float ABI (EABI hf)
set(_RPI1_CPU_FLAGS
    "-march=armv6zk -mtune=arm1176jzf-s -mfpu=vfp -mfloat-abi=hard")

set(CMAKE_C_FLAGS_INIT   "${_RPI1_CPU_FLAGS} -std=c11"   CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "${_RPI1_CPU_FLAGS} -std=c++20" CACHE INTERNAL "")

# --- Sysroot (опціонально) ------------------------------------------------
# Sysroot дозволяє лінкуватись проти бібліотек цільової системи.
# Отримати: скрипт scripts/sync-sysroot.sh або образ Raspberry Pi OS.
set(RPI_SYSROOT "" CACHE PATH
    "Шлях до sysroot Raspberry Pi (порожньо = збірка без sysroot)")

if(RPI_SYSROOT)
    if(NOT IS_DIRECTORY "${RPI_SYSROOT}")
        message(FATAL_ERROR
            "[Toolchain] RPI_SYSROOT не існує: '${RPI_SYSROOT}'")
    endif()
    set(CMAKE_SYSROOT "${RPI_SYSROOT}")
    if(NOT "${RPI_SYSROOT}" IN_LIST CMAKE_FIND_ROOT_PATH)
        list(APPEND CMAKE_FIND_ROOT_PATH "${RPI_SYSROOT}")
    endif()
    cross_toolchain_setup_sysroot()
else()
    if(CMAKE_CROSSCOMPILING)
        message(FATAL_ERROR
            "[RaspberryPi1] RPI_SYSROOT не задано. "
            "Для крос-компіляції задайте -DRPI_SYSROOT=<path>")
    endif()
    cross_toolchain_no_sysroot()
endif()
