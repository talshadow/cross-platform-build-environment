# cmake/toolchains/Clang.cmake
#
# Нативна збірка Clang/LLVM — x86_64
# Підтримує вибір конкретної версії через CLANG_VERSION.
#
# Ubuntu встановлює версійні пакети: clang-16, clang-17, clang-18 ...
# Для встановлення: sudo apt install clang-18 llvm-18
#
# Використання:
#   cmake -B build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/Clang.cmake \
#     [-DCLANG_VERSION=18]
#
# LTO:
#   Clang використовує ThinLTO (-flto=thin) або повний LTO (-flto).
#   Для коректної роботи LTO потрібні llvm-ar та llvm-ranlib (а не gcc-ar).
#   Цей toolchain шукає їх та прописує в CMAKE_AR / CMAKE_RANLIB.
#
# Лінкер:
#   За замовчуванням — системний ld. Для прискорення лінкування можна
#   використати lld: -DCLANG_USE_LLD=ON (встановлює -fuse-ld=lld).

cmake_minimum_required(VERSION 3.20)

set(CMAKE_SYSTEM_NAME      Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# --- Версія Clang -------------------------------------------------------------
set(CLANG_VERSION ""
    CACHE STRING "Версія Clang (напр. 18, 17, 16 або порожньо = системний clang)")

option(CLANG_USE_LLD
    "Використовувати lld замість системного ld (швидше лінкування)"
    OFF)

# --- Пошук компілятора -------------------------------------------------------
if(CLANG_VERSION)
    set(_clang_suffix "-${CLANG_VERSION}")
    find_program(CMAKE_C_COMPILER   "clang-${CLANG_VERSION}")
    find_program(CMAKE_CXX_COMPILER "clang++-${CLANG_VERSION}")

    if(NOT CMAKE_C_COMPILER OR NOT CMAKE_CXX_COMPILER)
        message(FATAL_ERROR
            "\n[Toolchain] Clang ${CLANG_VERSION} не знайдено.\n"
            "Встановіть: sudo apt install clang-${CLANG_VERSION} llvm-${CLANG_VERSION}\n"
            "Або не вказуйте версію (системний clang): -DCLANG_VERSION=\n")
    endif()
else()
    set(_clang_suffix "")
    find_program(CMAKE_C_COMPILER   "clang")
    find_program(CMAKE_CXX_COMPILER "clang++")

    if(NOT CMAKE_C_COMPILER OR NOT CMAKE_CXX_COMPILER)
        message(FATAL_ERROR
            "\n[Toolchain] clang не знайдено.\n"
            "Встановіть: sudo apt install clang llvm\n"
            "Або вкажіть конкретну версію: -DCLANG_VERSION=18\n")
    endif()
endif()

set(CMAKE_C_COMPILER   "${CMAKE_C_COMPILER}"   CACHE FILEPATH "C compiler"   FORCE)
set(CMAKE_CXX_COMPILER "${CMAKE_CXX_COMPILER}" CACHE FILEPATH "C++ compiler" FORCE)

# --- Утиліти LLVM (llvm-ar / llvm-ranlib потрібні для ThinLTO) ---------------
# llvm-ar та llvm-ranlib — аналоги gcc-ar/gcc-ranlib для Clang LTO.
# Без них ENABLE_LTO=ON з Clang дасть помилку: "file not recognized: File format not recognized".
find_program(_LLVM_AR     "llvm-ar${_clang_suffix}")
find_program(_LLVM_RANLIB "llvm-ranlib${_clang_suffix}")
find_program(_LLVM_NM     "llvm-nm${_clang_suffix}")

if(_LLVM_AR)
    set(CMAKE_AR     "${_LLVM_AR}"     CACHE FILEPATH "Archiver (LTO-aware)"  FORCE)
endif()
if(_LLVM_RANLIB)
    set(CMAKE_RANLIB "${_LLVM_RANLIB}" CACHE FILEPATH "Ranlib (LTO-aware)"    FORCE)
endif()
if(_LLVM_NM)
    set(CMAKE_NM     "${_LLVM_NM}"     CACHE FILEPATH "NM (LTO-aware)"        FORCE)
endif()

unset(_LLVM_AR)
unset(_LLVM_RANLIB)
unset(_LLVM_NM)

# --- Лінкер ------------------------------------------------------------------
# lld значно швидший ніж ld.bfd, особливо для великих проєктів.
# Потрібен пакет lld (або lld-N при конкретній версії LLVM).
if(CLANG_USE_LLD)
    find_program(_LLD "ld.lld${_clang_suffix}")
    if(NOT _LLD)
        find_program(_LLD "ld.lld")
    endif()
    if(_LLD)
        # -fuse-ld передається через прапори компілятора, а не CMAKE_LINKER
        set(CMAKE_EXE_LINKER_FLAGS_INIT    "-fuse-ld=lld" CACHE INTERNAL "")
        set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld" CACHE INTERNAL "")
        set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld" CACHE INTERNAL "")
        message(STATUS "[Clang] Лінкер: lld (${_LLD})")
    else()
        message(WARNING "[Clang] CLANG_USE_LLD=ON але lld не знайдено. "
            "Встановіть: sudo apt install lld${_clang_suffix}")
    endif()
    unset(_LLD)
endif()

# --- Прапори оптимізації для x86_64 -----------------------------------------
# -march=x86-64-v2 — розширений базовий x86_64 (SSE4.2, POPCNT)
# -mtune=generic   — збалансована оптимізація
set(CMAKE_C_FLAGS_INIT   "-march=x86-64-v2 -mtune=generic" CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "-march=x86-64-v2 -mtune=generic" CACHE INTERNAL "")

unset(_clang_suffix)

message(STATUS "[Clang] Компілятор: ${CMAKE_C_COMPILER}, AR: ${CMAKE_AR}")
