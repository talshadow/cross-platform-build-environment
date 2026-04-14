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

cmake_minimum_required(VERSION 3.20)

set(CMAKE_SYSTEM_NAME      Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# --- Версія GCC -----------------------------------------------------------
set(UBUNTU2404_GCC_VERSION "13"
    CACHE STRING "Версія GCC для Ubuntu 24.04 (13 або 14)")

set_property(CACHE UBUNTU2404_GCC_VERSION PROPERTY STRINGS "13" "14")

# --- Пошук компілятора ----------------------------------------------------
find_program(CMAKE_C_COMPILER   "gcc-${UBUNTU2404_GCC_VERSION}")
find_program(CMAKE_CXX_COMPILER "g++-${UBUNTU2404_GCC_VERSION}")

if(NOT CMAKE_C_COMPILER OR NOT CMAKE_CXX_COMPILER)
    message(FATAL_ERROR
        "\n[Toolchain] GCC ${UBUNTU2404_GCC_VERSION} не знайдено.\n"
        "Встановіть: sudo apt install gcc-${UBUNTU2404_GCC_VERSION} "
        "g++-${UBUNTU2404_GCC_VERSION}\n"
        "Або змініть версію: -DUBUNTU2404_GCC_VERSION=14\n")
endif()

set(CMAKE_C_COMPILER   "${CMAKE_C_COMPILER}"   CACHE FILEPATH "C compiler"   FORCE)
set(CMAKE_CXX_COMPILER "${CMAKE_CXX_COMPILER}" CACHE FILEPATH "C++ compiler" FORCE)

# --- Утиліти GCC (gcc-ar / gcc-ranlib потрібні для LTO) -------------------
# gcc-ar та gcc-ranlib — обгортки над ar/ranlib з підтримкою LTO плагіну.
# Без них `ar` не розуміє LTO-об'єкти і ENABLE_LTO=ON дасть помилку лінкування.
find_program(_GCC_AR     "gcc-ar-${UBUNTU2404_GCC_VERSION}")
find_program(_GCC_RANLIB "gcc-ranlib-${UBUNTU2404_GCC_VERSION}")
find_program(_GCC_NM     "gcc-nm-${UBUNTU2404_GCC_VERSION}")

if(_GCC_AR)
    set(CMAKE_AR     "${_GCC_AR}"     CACHE FILEPATH "Archiver (LTO-aware)"  FORCE)
endif()
if(_GCC_RANLIB)
    set(CMAKE_RANLIB "${_GCC_RANLIB}" CACHE FILEPATH "Ranlib (LTO-aware)"    FORCE)
endif()
if(_GCC_NM)
    set(CMAKE_NM     "${_GCC_NM}"     CACHE FILEPATH "NM (LTO-aware)"        FORCE)
endif()
unset(_GCC_AR)
unset(_GCC_RANLIB)
unset(_GCC_NM)

# --- Прапори оптимізації для x86_64 --------------------------------------
# -march=x86-64-v2  — розширений базовий x86_64 (SSE4.2, POPCNT), сумісний
#                     із переважною більшістю x86_64 CPU, випущених після 2009.
#                     Замініть на x86-64 якщо потрібна максимальна сумісність.
# -mtune=generic    — збалансована оптимізація
set(CMAKE_C_FLAGS_INIT   "-march=x86-64-v2 -mtune=generic" CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "-march=x86-64-v2 -mtune=generic" CACHE INTERNAL "")

message(STATUS "[Ubuntu2404] Компілятор: ${CMAKE_C_COMPILER}, AR: ${CMAKE_AR}")
