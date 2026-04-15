# cmake/external/Common.cmake
#
# Спільні утиліти для збірки сторонніх бібліотек через ExternalProject.
# Підключається автоматично через ExternalDeps.cmake — не включати напряму.
#
# Надає:
#   Змінні/кеш:
#     BUILD_ROOT               — коренева директорія збірки (~/build)
#     EXTERNAL_INSTALL_PREFIX  — префікс встановлення
#     EP_SOURCES_DIR           — кеш завантажених архівів сорців
#     USE_ORIGIN_RPATH         — прапор $ORIGIN rpath
#     _EP_NPROC                — кількість паралельних задач
#
#   Функції:
#     ep_cmake_args()                    — формує CMake-аргументи для EP
#     ep_imported_library()              — SHARED IMPORTED target
#     ep_imported_interface()            — INTERFACE IMPORTED target (header-only)
#     ep_imported_library_from_ep()      — SHARED IMPORTED + залежність від EP
#     ep_imported_interface_from_ep()    — INTERFACE IMPORTED + залежність від EP
#     _ep_collect_deps()                 — повертає список існуючих EP-цілей
#     _ep_cmake_to_meson_buildtype()     — конвертує CMAKE_BUILD_TYPE → meson --buildtype
#     _ep_require_meson()                — перевіряє наявність meson+ninja, FATAL_ERROR якщо нема
#     _ep_require_python_modules()       — перевіряє наявність Python3-модулів на хості

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
# BUILD_ROOT — коренева директорія збірки
# За замовчуванням ~/build, перевизначається через -DBUILD_ROOT=<path>
if(NOT DEFINED BUILD_ROOT OR BUILD_ROOT STREQUAL "")
    set(BUILD_ROOT "$ENV{HOME}/build"
        CACHE PATH "Коренева директорія збірки (за замовч. ~/build)")
endif()

# ---------------------------------------------------------------------------
# EXTERNAL_INSTALL_PREFIX
#
# База: ${BUILD_ROOT}/${CMAKE_PROJECT_NAME}/
# Шлях: ${BUILD_ROOT}/${CMAKE_PROJECT_NAME}/external/<toolchain>/<BuildType>
#
# Приклади (BUILD_ROOT=~/build, PROJECT=MyApp):
#   RPi4 Release  → ~/build/MyApp/external/RaspberryPi4/Release
#   Yocto Debug   → ~/build/MyApp/external/Yocto/Debug
#   Нативна       → ~/build/MyApp/external/native/Debug
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

    set(EXTERNAL_INSTALL_PREFIX
        "${BUILD_ROOT}/${CMAKE_PROJECT_NAME}/external/${_ep_toolchain_name}/${CMAKE_BUILD_TYPE}"
        CACHE PATH
        "Префікс встановлення сторонніх бібліотек (за замовченням: \${BUILD_ROOT}/\${PROJECT}/external/<toolchain>/<BuildType>)"
    )
    unset(_ep_toolchain_name)
endif()

file(MAKE_DIRECTORY "${EXTERNAL_INSTALL_PREFIX}")
message(STATUS "[ExternalDeps] Install prefix: ${EXTERNAL_INSTALL_PREFIX}")

# EP_SOURCES_DIR — спільна директорія git-клонів сорців для всіх toolchain
if(NOT DEFINED EP_SOURCES_DIR OR EP_SOURCES_DIR STREQUAL "")
    set(EP_SOURCES_DIR
        "${BUILD_ROOT}/${CMAKE_PROJECT_NAME}/external_sources"
        CACHE PATH "Директорія git-клонів сорців (спільна для всіх toolchain)")
endif()
file(MAKE_DIRECTORY "${EP_SOURCES_DIR}")
message(STATUS "[ExternalDeps] Sources dir: ${EP_SOURCES_DIR}")

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
# ep_find_scope(<out_var>)
#
# Повертає CMAKE_ARGS для пріоритету пошуку в ExternalProject суб-збірках.
# Охоплює find_library(), find_path(), find_package(), find_program().
#
# Пріоритет:
#   З sysroot (крос):      prefix → sysroot   (система повністю виключена)
#   Без sysroot (нативна): prefix → система   (звичайні правила після prefix)
#
# find_program() при крос-компіляції завжди шукає на хості (NEVER) —
# генератори коду (python3, perl тощо) мають бути хост-інструментами.
#
# Викликається автоматично з ep_cmake_args(). Можна викликати явно з
# Lib*.cmake для перевизначення scope окремої суб-збірки:
#
#   ep_find_scope(_scope_args)
#   ExternalProject_Add(foo_ep CMAKE_ARGS ${_foo_args} ${_scope_args} ...)
# ---------------------------------------------------------------------------
function(ep_find_scope out_var)
    if(CMAKE_SYSROOT)
        # Крос-компіляція: тільки наш prefix та sysroot,
        # системні шляхи хоста повністю виключені.
        set(${out_var}
            -DCMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=OFF
            -DCMAKE_FIND_USE_CMAKE_SYSTEM_PATH=OFF
            -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
            -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
            -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY
            -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
            PARENT_SCOPE)
    else()
        # Нативна збірка: наш prefix першим, потім звичайний системний пошук.
        set(${out_var}
            -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
            -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
            -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
            -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=BOTH
            PARENT_SCOPE)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# ep_cmake_args(<out_var> [extra -DKEY=VAL ...])
#
# Формує список аргументів для ExternalProject_Add(CMAKE_ARGS ...).
# Автоматично передає: toolchain, sysroot, компілятори, ar/ranlib/strip,
# пріоритет пошуку (ep_find_scope), RPATH.
# ---------------------------------------------------------------------------
function(ep_cmake_args out_var)
    set(_args
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
        -DCMAKE_INSTALL_PREFIX=${EXTERNAL_INSTALL_PREFIX}
        -DCMAKE_INSTALL_LIBDIR=lib
        -DBUILD_SHARED_LIBS=ON
    )

    # Пріоритет пошуку: prefix → sysroot|система (залежно від конфігурації)
    ep_find_scope(_scope_args)
    list(APPEND _args ${_scope_args})

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

# ---------------------------------------------------------------------------
# _ep_cmake_to_meson_buildtype(<out_var> [cmake_build_type])
#
# Перетворює CMake CMAKE_BUILD_TYPE на відповідний Meson --buildtype.
#
# Відображення:
#   Debug          → debug
#   Release        → release
#   RelWithDebInfo → debugoptimized
#   MinSizeRel     → minsize
#   (інше/порожнє) → debug
#
# Якщо другий аргумент не переданий — використовує CMAKE_BUILD_TYPE.
#
# Приклад:
#   _ep_cmake_to_meson_buildtype(_meson_bt)
#   ExternalProject_Add(foo_ep ... --buildtype=${_meson_bt} ...)
# ---------------------------------------------------------------------------
function(_ep_cmake_to_meson_buildtype out_var)
    if(ARGC GREATER 1)
        set(_bt "${ARGV1}")
    else()
        set(_bt "${CMAKE_BUILD_TYPE}")
    endif()

    if(_bt STREQUAL "Release")
        set(_meson "release")
    elseif(_bt STREQUAL "RelWithDebInfo")
        set(_meson "debugoptimized")
    elseif(_bt STREQUAL "MinSizeRel")
        set(_meson "minsize")
    else()
        set(_meson "debug")
    endif()

    set(${out_var} "${_meson}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# _ep_require_python_modules(<module1> [module2 ...])
#
# Перевіряє наявність Python3-модулів на хості (потрібні як host-tools
# під час збірки, наприклад для генерації коду — не залежності таргету).
# При відсутності видає FATAL_ERROR з командами встановлення для
# Ubuntu/Debian і Arch/CachyOS.
#
# Приклад:
#   _ep_require_python_modules(yaml ply)
# ---------------------------------------------------------------------------
function(_ep_require_python_modules)
    find_package(Python3 QUIET COMPONENTS Interpreter)
    if(NOT Python3_Interpreter_FOUND)
        message(FATAL_ERROR
            "[ExternalDeps] python3 не знайдено в PATH.\n"
            "  Ubuntu/Debian : sudo apt install python3\n"
            "  Arch/CachyOS  : sudo pacman -S python")
    endif()

    set(_missing_pkgs "")
    set(_missing_mods "")
    foreach(_mod ${ARGN})
        execute_process(
            COMMAND "${Python3_EXECUTABLE}" -c "import ${_mod}"
            RESULT_VARIABLE _rc
            OUTPUT_QUIET ERROR_QUIET)
        if(NOT _rc EQUAL 0)
            list(APPEND _missing_mods "${_mod}")
            # Відображення python-module → пакет для кожної OS
            if(_mod STREQUAL "yaml")
                list(APPEND _missing_pkgs
                    "apt:python3-yaml"
                    "pacman:python-yaml")
            elseif(_mod STREQUAL "ply")
                list(APPEND _missing_pkgs
                    "apt:python3-ply"
                    "pacman:python-ply")
            else()
                list(APPEND _missing_pkgs
                    "apt:python3-${_mod}"
                    "pacman:python-${_mod}")
            endif()
        endif()
    endforeach()

    if(NOT _missing_mods)
        return()
    endif()

    # Збираємо пакети по менеджерах
    set(_apt_pkgs "")
    set(_pacman_pkgs "")
    foreach(_entry ${_missing_pkgs})
        if(_entry MATCHES "^apt:(.+)$")
            list(APPEND _apt_pkgs "${CMAKE_MATCH_1}")
        elseif(_entry MATCHES "^pacman:(.+)$")
            list(APPEND _pacman_pkgs "${CMAKE_MATCH_1}")
        endif()
    endforeach()
    list(REMOVE_DUPLICATES _apt_pkgs)
    list(REMOVE_DUPLICATES _pacman_pkgs)
    string(JOIN " " _apt_str    ${_apt_pkgs})
    string(JOIN " " _pacman_str ${_pacman_pkgs})
    string(JOIN " " _mods_str   ${_missing_mods})

    message(FATAL_ERROR
        "[ExternalDeps] Відсутні Python3-модулі (host-tools): ${_mods_str}\n"
        "  Ubuntu/Debian : sudo apt install ${_apt_str}\n"
        "  Arch/CachyOS  : sudo pacman -S ${_pacman_str}\n"
        "Після встановлення повторіть: cmake --preset <preset>")
endfunction()

# ---------------------------------------------------------------------------
# _ep_require_meson()
#
# Перевіряє наявність meson та ninja в PATH.
# При відсутності зупиняє конфігурацію з FATAL_ERROR та підказкою
# щодо встановлення для Ubuntu/Debian і Arch/CachyOS.
#
# Викликати перед ExternalProject_Add у кожному Lib*.cmake що потребує Meson.
# ---------------------------------------------------------------------------
function(_ep_require_meson)
    find_program(_ep_rm_meson meson)
    find_program(_ep_rm_ninja ninja)

    set(_missing "")
    if(NOT _ep_rm_meson)
        list(APPEND _missing "meson")
    endif()
    if(NOT _ep_rm_ninja)
        list(APPEND _missing "ninja")
    endif()

    if(_missing)
        string(JOIN " " _missing_str ${_missing})
        message(FATAL_ERROR
            "[ExternalDeps] Відсутні інструменти для збірки Meson-проектів: ${_missing_str}\n"
            "  Ubuntu/Debian : sudo apt install meson ninja-build\n"
            "  Arch/CachyOS  : sudo pacman -S meson ninja\n"
            "Після встановлення повторіть: cmake --preset <preset>")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# _meson_generate_cross_file(<out_var>)
#
# Генерує файл meson-cross.ini для крос-компіляції (якщо CMAKE_CROSSCOMPILING).
# Повертає в <out_var> список аргументів для meson setup:
#   "--cross-file" "<шлях>" — при крос-компіляції
#   "" (порожньо)           — при нативній збірці
#
# Залежить від CMake змінних: CMAKE_C/CXX_COMPILER, CMAKE_AR, CMAKE_STRIP,
#   CMAKE_SYSTEM_PROCESSOR, CMAKE_SYSROOT.
# ---------------------------------------------------------------------------
function(_meson_generate_cross_file out_var)
    if(NOT CMAKE_CROSSCOMPILING)
        set(${out_var} "" PARENT_SCOPE)
        return()
    endif()

    # Map CMAKE_SYSTEM_PROCESSOR → Meson cpu_family
    string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _proc)
    if(_proc MATCHES "^aarch64|arm64")
        set(_meson_cpu_family "aarch64")
    elseif(_proc MATCHES "^arm")
        set(_meson_cpu_family "arm")
    elseif(_proc MATCHES "^x86_64|amd64")
        set(_meson_cpu_family "x86_64")
    elseif(_proc MATCHES "^i.86|^x86$")
        set(_meson_cpu_family "x86")
    elseif(_proc MATCHES "^riscv64")
        set(_meson_cpu_family "riscv64")
    else()
        set(_meson_cpu_family "${_proc}")
    endif()

    # Бінарні утиліти зі змінних toolchain
    set(_mc_ar    "${CMAKE_AR}")
    set(_mc_strip "${CMAKE_STRIP}")
    if(NOT _mc_ar)
        set(_mc_ar "ar")
    endif()
    if(NOT _mc_strip)
        set(_mc_strip "strip")
    endif()

    # Рядки sysroot та pkg-config для секції [properties]
    set(_mc_sysroot_line    "")
    set(_mc_pkgconfig_line  "")
    if(CMAKE_SYSROOT)
        set(_mc_sysroot_line   "sys_root = '${CMAKE_SYSROOT}'")
        set(_mc_pkgconfig_line
            "pkg_config_libdir = '${CMAKE_SYSROOT}/usr/lib/pkgconfig:${CMAKE_SYSROOT}/usr/share/pkgconfig'")
    endif()

    set(_cross_file "${CMAKE_BINARY_DIR}/_ep_cfg/meson-cross.ini")
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/_ep_cfg")
    file(WRITE "${_cross_file}"
"[binaries]
c = '${CMAKE_C_COMPILER}'
cpp = '${CMAKE_CXX_COMPILER}'
ar = '${_mc_ar}'
strip = '${_mc_strip}'
pkgconfig = 'pkg-config'

[properties]
${_mc_sysroot_line}
${_mc_pkgconfig_line}

[host_machine]
system = 'linux'
cpu_family = '${_meson_cpu_family}'
cpu = '${_meson_cpu_family}'
endian = 'little'
")
    set(${out_var} "--cross-file" "${_cross_file}" PARENT_SCOPE)
endfunction()
