# cmake/toolchains/Ubuntu2404.cmake
#
# Toolchain для Ubuntu 24.04 LTS (Noble Numbat) — x86_64
# Фіксує конкретну версію GCC для відтворюваних збірок.
#
# Ubuntu 24.04 постачає GCC 13 (default), GCC 14.
# Для встановлення: sudo apt install gcc-13 g++-13
#
# Використання:
#   cmake -B build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/Ubuntu2404.cmake \
#     [-DUBUNTU2404_GCC_VERSION=14]

cmake_minimum_required(VERSION 3.28)

set(CMAKE_SYSTEM_NAME      Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# --- Версія GCC -----------------------------------------------------------
set(UBUNTU2404_GCC_VERSION "13"
    CACHE STRING "Версія GCC для Ubuntu 24.04 (13 або 14)")

set_property(CACHE UBUNTU2404_GCC_VERSION PROPERTY STRINGS "13" "14")

include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

# --- Пошук компілятора ----------------------------------------------------
# gcc-ar/ranlib/nm — LTO-aware обгортки; без них ENABLE_LTO=ON дасть помилку.
cross_toolchain_find_versioned_native_gcc(
    "${UBUNTU2404_GCC_VERSION}"
    "UBUNTU2404_GCC_VERSION")

# --- Прапори оптимізації для x86_64 --------------------------------------
# -march=x86-64-v2  — розширений базовий x86_64 (SSE4.2, POPCNT), сумісний
#                     із переважною більшістю x86_64 CPU, випущених після 2009.
#                     Замініть на x86-64 якщо потрібна максимальна сумісність.
# -mtune=generic    — збалансована оптимізація
set(CMAKE_C_FLAGS_INIT   "-march=x86-64-v2 -mtune=generic -std=gnu11"   CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "-march=x86-64-v2 -mtune=generic -std=c++20" CACHE INTERNAL "")

message(STATUS "[Ubuntu2404] Компілятор: ${CMAKE_C_COMPILER}, AR: ${CMAKE_AR}")
