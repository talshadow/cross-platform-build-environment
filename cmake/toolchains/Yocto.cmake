# cmake/toolchains/Yocto.cmake
#
# Toolchain для Yocto Linux (через Yocto SDK)
#
# Yocto SDK надає скрипт середовища, який встановлює всі необхідні
# змінні ($CC, $CXX, $SDKTARGETSYSROOT тощо).
# Перед конфігурацією CMake ОБОВ'ЯЗКОВО активуйте SDK:
#
#   source /opt/poky/<version>/environment-setup-<target>-poky-linux
#   cmake -B build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/Yocto.cmake
#
# Або вкажіть шлях до SDK явно:
#   cmake -B build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/Yocto.cmake \
#     -DYOCTO_SDK_SYSROOT=/opt/poky/<version>/sysroots/<target>
#     -DYOCTO_SDK_HOST_SYSROOT=/opt/poky/<version>/sysroots/x86_64-pokysdk-linux
#
# Архітектура визначається автоматично зі змінних SDK.

cmake_minimum_required(VERSION 3.28)

# --- Визначення архітектури з SDK -----------------------------------------
# OECORE_TARGET_ARCH встановлюється скриптом environment-setup-*
if(DEFINED ENV{OECORE_TARGET_ARCH})
    set(_YOCTO_ARCH "$ENV{OECORE_TARGET_ARCH}")
else()
    # Fallback: спробувати визначити з CROSS_COMPILE або CC
    if(DEFINED ENV{CROSS_COMPILE})
        string(REGEX MATCH "^([^-]+)" _YOCTO_ARCH "$ENV{CROSS_COMPILE}")
    endif()
endif()

if(_YOCTO_ARCH MATCHES "^aarch64")
    set(CMAKE_SYSTEM_PROCESSOR aarch64)
elseif(_YOCTO_ARCH MATCHES "^arm")
    set(CMAKE_SYSTEM_PROCESSOR arm)
elseif(_YOCTO_ARCH MATCHES "^x86_64")
    set(CMAKE_SYSTEM_PROCESSOR x86_64)
elseif(_YOCTO_ARCH MATCHES "^i.86")
    set(CMAKE_SYSTEM_PROCESSOR i686)
elseif(_YOCTO_ARCH MATCHES "^riscv64")
    set(CMAKE_SYSTEM_PROCESSOR riscv64)
else()
    message(WARNING
        "[Yocto] Не вдалося визначити архітектуру ('${_YOCTO_ARCH}'). "
        "Задайте CMAKE_SYSTEM_PROCESSOR вручну.")
    set(CMAKE_SYSTEM_PROCESSOR "${_YOCTO_ARCH}")
endif()

set(CMAKE_SYSTEM_NAME Linux)

# --- Компілятори з SDK -----------------------------------------------------
# Yocto SDK зберігає повний шлях + прапори у $CC/$CXX
# Розбиваємо на виконуваний файл і прапори.
if(DEFINED ENV{CC})
    separate_arguments(_CC_ARGS NATIVE_COMMAND "$ENV{CC}")
    list(GET _CC_ARGS 0 _CC_EXE)
    list(REMOVE_AT _CC_ARGS 0)

    set(CMAKE_C_COMPILER "${_CC_EXE}" CACHE FILEPATH "C compiler" FORCE)
    # Прапори з $CC + базовий стандарт C11 (strict, без -D_GNU_SOURCE)
    string(JOIN " " _CC_FLAGS ${_CC_ARGS})
    set(CMAKE_C_FLAGS_INIT "${_CC_FLAGS} -std=c11" CACHE INTERNAL "")
else()
    message(FATAL_ERROR
        "[Yocto] Змінна середовища CC не визначена.\n"
        "Активуйте Yocto SDK: source /opt/poky/<ver>/environment-setup-*")
endif()

if(DEFINED ENV{CXX})
    separate_arguments(_CXX_ARGS NATIVE_COMMAND "$ENV{CXX}")
    list(GET _CXX_ARGS 0 _CXX_EXE)
    list(REMOVE_AT _CXX_ARGS 0)

    set(CMAKE_CXX_COMPILER "${_CXX_EXE}" CACHE FILEPATH "C++ compiler" FORCE)
    string(JOIN " " _CXX_FLAGS ${_CXX_ARGS})
    set(CMAKE_CXX_FLAGS_INIT "${_CXX_FLAGS} -std=c++20" CACHE INTERNAL "")
else()
    message(FATAL_ERROR
        "[Yocto] Змінна середовища CXX не визначена.\n"
        "Активуйте Yocto SDK: source /opt/poky/<ver>/environment-setup-*")
endif()

# AR, STRIP, RANLIB з SDK
foreach(_TOOL AR STRIP RANLIB LD OBJCOPY OBJDUMP NM READELF)
    if(DEFINED ENV{${_TOOL}})
        separate_arguments(_TOOL_ARGS NATIVE_COMMAND "$ENV{${_TOOL}}")
        list(GET _TOOL_ARGS 0 _TOOL_EXE)
        set(CMAKE_${_TOOL} "${_TOOL_EXE}" CACHE FILEPATH "${_TOOL}" FORCE)
    endif()
endforeach()

# --- Sysroot ---------------------------------------------------------------
set(YOCTO_SDK_SYSROOT "" CACHE PATH
    "Target sysroot Yocto SDK. Якщо порожньо — береться з \$SDKTARGETSYSROOT")

if(YOCTO_SDK_SYSROOT)
    set(_SYSROOT "${YOCTO_SDK_SYSROOT}")
elseif(DEFINED ENV{SDKTARGETSYSROOT})
    set(_SYSROOT "$ENV{SDKTARGETSYSROOT}")
else()
    message(FATAL_ERROR
        "[Yocto] Sysroot не визначено.\n"
        "Активуйте SDK або задайте -DYOCTO_SDK_SYSROOT=<path>")
endif()

if(NOT IS_DIRECTORY "${_SYSROOT}")
    message(FATAL_ERROR
        "[Yocto] Sysroot не існує: '${_SYSROOT}'")
endif()

set(CMAKE_SYSROOT "${_SYSROOT}")
if(NOT "${_SYSROOT}" IN_LIST CMAKE_FIND_ROOT_PATH)
    list(APPEND CMAKE_FIND_ROOT_PATH "${_SYSROOT}")
endif()

include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")
cross_toolchain_setup_sysroot()

# --- PKG_CONFIG для cross-збірки ------------------------------------------
# Використовуємо pkg-config з SDK, а не з хост-системи
if(DEFINED ENV{PKG_CONFIG})
    set(PKG_CONFIG_EXECUTABLE "$ENV{PKG_CONFIG}" CACHE FILEPATH "pkg-config" FORCE)
elseif(DEFINED ENV{OECORE_NATIVE_SYSROOT})
    find_program(PKG_CONFIG_EXECUTABLE pkg-config
        PATHS "$ENV{OECORE_NATIVE_SYSROOT}/usr/bin"
        NO_DEFAULT_PATH)
endif()
