# cmake/toolchains/Ubuntu2004.cmake
#
# Toolchain для Ubuntu 20.04 LTS (Focal Fossa) — x86_64
# Фіксує конкретну версію GCC для відтворюваних збірок.
#
# Ubuntu 20.04 постачає GCC 9 (default), GCC 10.
# Для встановлення: sudo apt install gcc-10 g++-10
#
# Використання:
#   cmake -B build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/Ubuntu2004.cmake \
#     [-DUBUNTU2004_GCC_VERSION=10]

cmake_minimum_required(VERSION 3.28)

set(CMAKE_SYSTEM_NAME      Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# --- Версія GCC -----------------------------------------------------------
set(UBUNTU2004_GCC_VERSION "10"
    CACHE STRING "Версія GCC для Ubuntu 20.04 (9 або 10)")

set_property(CACHE UBUNTU2004_GCC_VERSION PROPERTY STRINGS "9" "10")

include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

# --- Пошук компілятора ----------------------------------------------------
# gcc-ar/ranlib/nm — LTO-aware обгортки; без них ENABLE_LTO=ON дасть помилку.
cross_toolchain_find_versioned_native_gcc(
    "${UBUNTU2004_GCC_VERSION}"
    "UBUNTU2004_GCC_VERSION")

# --- Прапори оптимізації для x86_64 --------------------------------------
# -march=x86-64    — базовий x86_64 (сумісність з будь-яким x86_64)
# -mtune=generic   — оптимізація для "середнього" x86_64 процесора
set(CMAKE_C_FLAGS_INIT   "-march=x86-64 -mtune=generic -std=gnu11"   CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "-march=x86-64 -mtune=generic -std=c++20" CACHE INTERNAL "")

message(STATUS "[Ubuntu2004] Компілятор: ${CMAKE_C_COMPILER}, AR: ${CMAKE_AR}")
