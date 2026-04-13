# cmake/external/Common.cmake
#
# Спільні утиліти для збірки сторонніх бібліотек через ExternalProject.
# Підключається автоматично через ExternalDeps.cmake — не включати напряму.
#
# Надає:
#   Змінні/кеш:
#     EXTERNAL_INSTALL_PREFIX  — префікс встановлення
#     USE_ORIGIN_RPATH         — прапор $ORIGIN rpath
#     _EP_NPROC                — кількість паралельних задач
#
#   Функції:
#     ep_cmake_args()                 — формує CMake-аргументи для EP
#     ep_imported_library()           — SHARED IMPORTED target
#     ep_imported_interface()         — INTERFACE IMPORTED target (header-only)
#     ep_imported_library_from_ep()   — SHARED IMPORTED + залежність від EP
#     ep_imported_interface_from_ep() — INTERFACE IMPORTED + залежність від EP
#     _ep_collect_deps()              — повертає список існуючих EP-цілей

cmake_minimum_required(VERSION 3.20)
include(ExternalProject)
include(ProcessorCount)

# Захист від повторного підключення
if(DEFINED _EP_COMMON_INCLUDED)
    return()
endif()
set(_EP_COMMON_INCLUDED TRUE)

# ---------------------------------------------------------------------------
# Кількість паралельних задач
# ---------------------------------------------------------------------------
ProcessorCount(_EP_NPROC)
if(_EP_NPROC EQUAL 0)
    set(_EP_NPROC 4)
endif()

# ---------------------------------------------------------------------------
# EXTERNAL_INSTALL_PREFIX
#
# За замовченням: ../External/<toolchain>/<BuildType>
# де ..  — батьківська директорія відносно CMAKE_BINARY_DIR
#
# Приклади (CMAKE_BINARY_DIR = build/rpi4-release):
#   RPi4 Release  → build/External/RaspberryPi4/Release
#   Yocto Debug   → build/External/Yocto/Debug
#   Нативна       → build/External/native/Debug
#
# Назва тулчейна — ім'я файлу toolchain без розширення .cmake.
# Якщо toolchain не заданий — "native".
# ---------------------------------------------------------------------------
if(NOT DEFINED EXTERNAL_INSTALL_PREFIX OR EXTERNAL_INSTALL_PREFIX STREQUAL "")
    # Визначаємо назву тулчейна
    if(CMAKE_TOOLCHAIN_FILE)
        get_filename_component(_ep_toolchain_name "${CMAKE_TOOLCHAIN_FILE}" NAME_WE)
    else()
        set(_ep_toolchain_name "native")
    endif()

    # ../External відносно CMAKE_BINARY_DIR
    get_filename_component(_ep_bin_parent "${CMAKE_BINARY_DIR}" DIRECTORY)
    set(EXTERNAL_INSTALL_PREFIX
        "${_ep_bin_parent}/External/${_ep_toolchain_name}/${CMAKE_BUILD_TYPE}"
        CACHE PATH
        "Префікс встановлення сторонніх бібліотек (за замовченням: ../External/<toolchain>/<BuildType>)"
    )
    unset(_ep_bin_parent)
    unset(_ep_toolchain_name)
endif()

file(MAKE_DIRECTORY "${EXTERNAL_INSTALL_PREFIX}")
message(STATUS "[ExternalDeps] Install prefix: ${EXTERNAL_INSTALL_PREFIX}")

# Додаємо до CMAKE_PREFIX_PATH і CMAKE_FIND_ROOT_PATH щоб find_package
# знаходив вже встановлені бібліотеки навіть у крос-режимі (ONLY mode).
list(PREPEND CMAKE_PREFIX_PATH   "${EXTERNAL_INSTALL_PREFIX}")
list(PREPEND CMAKE_FIND_ROOT_PATH "${EXTERNAL_INSTALL_PREFIX}")

# ---------------------------------------------------------------------------
# RPATH: $ORIGIN/../lib — відносний до бінарника, портабельний для RPi
# ---------------------------------------------------------------------------
option(USE_ORIGIN_RPATH
    "Вбудовувати \$ORIGIN-відносний RPATH у встановлені бінарні файли"
    ON)

# ---------------------------------------------------------------------------
# ep_cmake_args(<out_var> [extra -DKEY=VAL ...])
#
# Формує список аргументів для ExternalProject_Add(CMAKE_ARGS ...).
# Автоматично передає: toolchain, sysroot, компілятори, ar/ranlib/strip, RPATH.
# ---------------------------------------------------------------------------
function(ep_cmake_args out_var)
    set(_args
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
        -DCMAKE_INSTALL_PREFIX=${EXTERNAL_INSTALL_PREFIX}
        -DBUILD_SHARED_LIBS=ON
    )

    # Toolchain
    if(CMAKE_TOOLCHAIN_FILE)
        list(APPEND _args -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE})
    endif()

    # Компілятори (явно — на випадок якщо toolchain не переданий окремо)
    if(CMAKE_C_COMPILER)
        list(APPEND _args -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER})
    endif()
    if(CMAKE_CXX_COMPILER)
        list(APPEND _args -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER})
    endif()

    # Sysroot
    if(CMAKE_SYSROOT)
        list(APPEND _args -DCMAKE_SYSROOT=${CMAKE_SYSROOT})
    endif()
    if(RPI_SYSROOT)
        list(APPEND _args -DRPI_SYSROOT=${RPI_SYSROOT})
    endif()
    if(YOCTO_SDK_SYSROOT)
        list(APPEND _args -DYOCTO_SDK_SYSROOT=${YOCTO_SDK_SYSROOT})
    endif()

    # Бінарні утиліти (важливо для крос-компіляції)
    if(CMAKE_AR)
        list(APPEND _args -DCMAKE_AR=${CMAKE_AR})
    endif()
    if(CMAKE_RANLIB)
        list(APPEND _args -DCMAKE_RANLIB=${CMAKE_RANLIB})
    endif()
    if(CMAKE_STRIP)
        list(APPEND _args -DCMAKE_STRIP=${CMAKE_STRIP})
    endif()
    if(CMAKE_LINKER)
        list(APPEND _args -DCMAKE_LINKER=${CMAKE_LINKER})
    endif()

    # RPATH
    if(USE_ORIGIN_RPATH)
        list(APPEND _args
            "-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib"
            -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
            -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
        )
    endif()

    # Додаткові аргументи від виклику
    if(ARGN)
        list(APPEND _args ${ARGN})
    endif()

    set(${out_var} ${_args} PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# ep_imported_library(<target> <lib_path> <inc_dir>)
#
# Створює SHARED IMPORTED GLOBAL target.
# Безпечно для повторного виклику (no-op якщо target вже існує).
# ---------------------------------------------------------------------------
function(ep_imported_library target lib_path inc_dir)
    if(TARGET ${target})
        return()
    endif()
    add_library(${target} SHARED IMPORTED GLOBAL)
    set_target_properties(${target} PROPERTIES
        IMPORTED_LOCATION             "${lib_path}"
        INTERFACE_INCLUDE_DIRECTORIES "${inc_dir}"
    )
endfunction()

# ---------------------------------------------------------------------------
# ep_imported_interface(<target> <inc_dir>)
#
# Створює INTERFACE IMPORTED GLOBAL target (header-only бібліотека).
# ---------------------------------------------------------------------------
function(ep_imported_interface target inc_dir)
    if(TARGET ${target})
        return()
    endif()
    add_library(${target} INTERFACE IMPORTED GLOBAL)
    set_target_properties(${target} PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${inc_dir}"
    )
endfunction()

# ---------------------------------------------------------------------------
# ep_imported_library_from_ep(<target> <ep_name> <lib_path> <inc_dir>)
#
# Як ep_imported_library, але додає add_dependencies на ExternalProject.
# Виклик ПІСЛЯ ExternalProject_Add.
# ---------------------------------------------------------------------------
function(ep_imported_library_from_ep target ep_name lib_path inc_dir)
    ep_imported_library(${target} "${lib_path}" "${inc_dir}")
    add_dependencies(${target} ${ep_name})
endfunction()

# ---------------------------------------------------------------------------
# ep_imported_interface_from_ep(<target> <ep_name> <inc_dir>)
#
# Як ep_imported_interface, але з залежністю від ExternalProject.
# ---------------------------------------------------------------------------
function(ep_imported_interface_from_ep target ep_name inc_dir)
    ep_imported_interface(${target} "${inc_dir}")
    add_dependencies(${target} ${ep_name})
endfunction()

# ---------------------------------------------------------------------------
# _ep_collect_deps(<out_var> [ep_target1 ep_target2 ...])
#
# Повертає список тих EP-цілей що реально оголошені (TARGET існує).
# Повертає ТІЛЬКИ імена цілей — без ключового слова DEPENDS.
#
# Приклад:
#   _ep_collect_deps(_deps libjpeg_ep libpng_ep)
#   ExternalProject_Add(libtiff_ep DEPENDS ${_deps} ...)
#
# Безпечно: якщо _deps порожній, DEPENDS ${_deps} розширюється в нічого.
# ---------------------------------------------------------------------------
function(_ep_collect_deps out_var)
    set(_existing "")
    foreach(_ep ${ARGN})
        if(TARGET ${_ep})
            list(APPEND _existing ${_ep})
        endif()
    endforeach()
    set(${out_var} ${_existing} PARENT_SCOPE)
endfunction()
