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

cmake_minimum_required(VERSION 3.20)

set(CMAKE_SYSTEM_NAME      Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# --- Версія GCC -----------------------------------------------------------
set(UBUNTU2004_GCC_VERSION "10"
    CACHE STRING "Версія GCC для Ubuntu 20.04 (9 або 10)")

set_property(CACHE UBUNTU2004_GCC_VERSION PROPERTY STRINGS "9" "10")

# --- Пошук компілятора ----------------------------------------------------
find_program(CMAKE_C_COMPILER   "gcc-${UBUNTU2004_GCC_VERSION}")
find_program(CMAKE_CXX_COMPILER "g++-${UBUNTU2004_GCC_VERSION}")

if(NOT CMAKE_C_COMPILER OR NOT CMAKE_CXX_COMPILER)
    message(FATAL_ERROR
        "\n[Toolchain] GCC ${UBUNTU2004_GCC_VERSION} не знайдено.\n"
        "Встановіть: sudo apt install gcc-${UBUNTU2004_GCC_VERSION} "
        "g++-${UBUNTU2004_GCC_VERSION}\n"
        "Або змініть версію: -DUBUNTU2004_GCC_VERSION=9\n")
endif()

set(CMAKE_C_COMPILER   "${CMAKE_C_COMPILER}"   CACHE FILEPATH "C compiler"   FORCE)
set(CMAKE_CXX_COMPILER "${CMAKE_CXX_COMPILER}" CACHE FILEPATH "C++ compiler" FORCE)

# --- Утиліти GCC (gcc-ar / gcc-ranlib потрібні для LTO) -------------------
# gcc-ar та gcc-ranlib — обгортки над ar/ranlib з підтримкою LTO плагіну.
# Без них `ar` не розуміє LTO-об'єкти і ENABLE_LTO=ON дасть помилку лінкування.
find_program(_GCC_AR     "gcc-ar-${UBUNTU2004_GCC_VERSION}")
find_program(_GCC_RANLIB "gcc-ranlib-${UBUNTU2004_GCC_VERSION}")
find_program(_GCC_NM     "gcc-nm-${UBUNTU2004_GCC_VERSION}")

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
# -march=x86-64    — базовий x86_64 (сумісність з будь-яким x86_64)
# -mtune=generic   — оптимізація для "середнього" x86_64 процесора
set(CMAKE_C_FLAGS_INIT   "-march=x86-64 -mtune=generic" CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "-march=x86-64 -mtune=generic" CACHE INTERNAL "")

message(STATUS "[Ubuntu2004] Компілятор: ${CMAKE_C_COMPILER}, AR: ${CMAKE_AR}")
