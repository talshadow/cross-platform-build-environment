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
#     _ep_create_sysroot_lib_scripts()   — створює libm.so linker script → sysroot (крос-компіляція)
#     ep_track_cmake_file()              — авторебілд при зміні Lib*.cmake; таргети -reset і -rebuild

cmake_minimum_required(VERSION 3.28)
include(ExternalProject)
include(ProcessorCount)

# Захист від повторного підключення
if(DEFINED _EP_COMMON_INCLUDED)
    return()
endif()
set(_EP_COMMON_INCLUDED TRUE)

# RuntimeDeps.cmake — підключаємо відразу щоб ep_register_runtime_dirs()
# був доступний у всіх Lib*.cmake без додаткових include().
include("${CMAKE_CURRENT_LIST_DIR}/../modules/RuntimeDeps.cmake")

# ---------------------------------------------------------------------------
# _EP_PLATFORM_* — визначення платформи для Lib*.cmake файлів
#
# Модульні змінні (не кешуються, не видимі користувачу):
#   _EP_PLATFORM_RPI    — BOOL: ціль — будь-який Raspberry Pi
#   _EP_PLATFORM_RPI4   — BOOL: ціль — RPi 4/400/CM4 (BCM2711, VC4 ISP)
#   _EP_PLATFORM_RPI5   — BOOL: ціль — RPi 5/CM5 (BCM2712, PiSP ISP)
#   _EP_PLATFORM_YOCTO  — BOOL: ціль — Yocto Linux
#   _EP_PLATFORM_X86_64 — BOOL: ціль — x86_64
#   _EP_PLATFORM_ARM    — BOOL: ціль — ARM (aarch64 або arm32)
#
# Якщо cross_detect_platform() вже викликано — перевикористовує PLATFORM_*
# кеш-змінні. Інакше виконує інлайн-детекцію (та сама логіка, без побічних
# ефектів на кеш).
# ---------------------------------------------------------------------------
if(DEFINED PLATFORM_NAME)
    set(_EP_PLATFORM_RPI    ${PLATFORM_RPI})
    set(_EP_PLATFORM_RPI4   ${PLATFORM_RPI4})
    set(_EP_PLATFORM_RPI5   ${PLATFORM_RPI5})
    set(_EP_PLATFORM_YOCTO  ${PLATFORM_YOCTO})
    set(_EP_PLATFORM_X86_64 ${PLATFORM_X86_64})
    set(_EP_PLATFORM_ARM    ${PLATFORM_ARM})
else()
    set(_ep_pd_rpi   FALSE)
    set(_ep_pd_rpi4  FALSE)
    set(_ep_pd_rpi5  FALSE)
    set(_ep_pd_yocto FALSE)
    set(_ep_pd_name  "Unknown")

    if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|armv[6-8]|^arm")
        set(_ep_pd_arm TRUE)
        set(_ep_pd_x86 FALSE)
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
        set(_ep_pd_arm FALSE)
        set(_ep_pd_x86 TRUE)
    else()
        set(_ep_pd_arm FALSE)
        set(_ep_pd_x86 FALSE)
    endif()

    if(CMAKE_CROSSCOMPILING)
        get_filename_component(_ep_pd_tc "${CMAKE_TOOLCHAIN_FILE}" NAME_WE)
        if(_ep_pd_tc MATCHES "RaspberryPi([0-9]+)")
            set(_ep_pd_rpi  TRUE)
            set(_ep_pd_name "RPi${CMAKE_MATCH_1}")
        elseif(_ep_pd_tc MATCHES "Yocto")
            set(_ep_pd_yocto TRUE)
            set(_ep_pd_name  "Yocto")
        else()
            set(_ep_pd_name "${_ep_pd_tc}")
        endif()
        unset(_ep_pd_tc)
    else()
        if(_ep_pd_arm AND EXISTS "/proc/device-tree/model")
            file(READ "/proc/device-tree/model" _ep_pd_model)
            if(_ep_pd_model MATCHES "Raspberry Pi ([0-9]+)")
                set(_ep_pd_rpi  TRUE)
                set(_ep_pd_name "RPi${CMAKE_MATCH_1}")
            elseif(_ep_pd_model MATCHES "Raspberry Pi")
                set(_ep_pd_rpi  TRUE)
                set(_ep_pd_name "RPi")
            endif()
            unset(_ep_pd_model)
        elseif(_ep_pd_x86)
            set(_ep_pd_name "Linux-x86_64")
        else()
            set(_ep_pd_name "Linux-${CMAKE_SYSTEM_PROCESSOR}")
        endif()
    endif()

    if(_ep_pd_name MATCHES "^RPi([0-9]+)")
        if(CMAKE_MATCH_1 STREQUAL "4")
            set(_ep_pd_rpi4 TRUE)
        elseif(CMAKE_MATCH_1 STREQUAL "5")
            set(_ep_pd_rpi5 TRUE)
        endif()
    endif()

    set(_EP_PLATFORM_RPI    ${_ep_pd_rpi})
    set(_EP_PLATFORM_RPI4   ${_ep_pd_rpi4})
    set(_EP_PLATFORM_RPI5   ${_ep_pd_rpi5})
    set(_EP_PLATFORM_YOCTO  ${_ep_pd_yocto})
    set(_EP_PLATFORM_X86_64 ${_ep_pd_x86})
    set(_EP_PLATFORM_ARM    ${_ep_pd_arm})

    unset(_ep_pd_rpi)
    unset(_ep_pd_rpi4)
    unset(_ep_pd_rpi5)
    unset(_ep_pd_yocto)
    unset(_ep_pd_name)
    unset(_ep_pd_arm)
    unset(_ep_pd_x86)
endif()

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

# ---------------------------------------------------------------------------
# _ep_create_sysroot_lib_scripts()
#
# При крос-компіляції створює GNU ld linker scripts у EXTERNAL_INSTALL_PREFIX/lib/:
#   libm.so  → sysroot libm.so.6
#   libc.so  → sysroot libc.so.6
#
# Проблема: Ubuntu 24.04 host GCC 13+ компілює виклики strtoul/strtod/etc
# у __isoc23_*@GLIBC_2.38 (C23 варіанти). EP-бібліотеки, зібрані на host
# і злінковані проти host libc/libm, тягнуть ці символи. Цільова система
# (наприклад RPi з GLIBC 2.36) їх не має → "undefined reference".
#
# Рішення: linker scripts у EXTERNAL_INSTALL_PREFIX/lib/ перехоплюють пошук
# libc/libm і перенаправляють на sysroot-версії з правильними символами.
# EXTERNAL_INSTALL_PREFIX стоїть першим у CMAKE_PREFIX_PATH → знаходиться
# раніше за host бібліотеки.
#
# GNU ld з --sysroot додає sysroot-префікс до абсолютних шляхів у linker
# scripts, тому GROUP() містить шлях ВІДНОСНО sysroot-кореня.
#
# Викликається автоматично під час конфігурації — ручний виклик не потрібен.
# ---------------------------------------------------------------------------

# Внутрішній хелпер: знаходить <soname> у sysroot і створює linker script <script_name>.so
function(_ep_write_sysroot_lib_script lib_dir script_name soname)
    set(_candidates "")
    if(CMAKE_LIBRARY_ARCHITECTURE)
        list(APPEND _candidates
            "${CMAKE_SYSROOT}/lib/${CMAKE_LIBRARY_ARCHITECTURE}/${soname}"
            "${CMAKE_SYSROOT}/usr/lib/${CMAKE_LIBRARY_ARCHITECTURE}/${soname}"
        )
    endif()
    list(APPEND _candidates
        "${CMAKE_SYSROOT}/lib/${soname}"
        "${CMAKE_SYSROOT}/usr/lib/${soname}"
    )

    set(_found "")
    foreach(_c IN LISTS _candidates)
        if(EXISTS "${_c}")
            set(_found "${_c}")
            break()
        endif()
    endforeach()

    if(NOT _found)
        message(WARNING "[Common] ${soname} не знайдено у sysroot '${CMAKE_SYSROOT}' — "
            "${script_name} linker script не створено.")
        return()
    endif()

    # Використовуємо повний абсолютний шлях до файлу в sysroot.
    # Наш linker script знаходиться ПОЗА sysroot (в EXTERNAL_INSTALL_PREFIX),
    # тому GNU ld НЕ застосовує --sysroot-rewriting до шляхів всередині нього.
    # Абсолютний шлях типу /srv/rpi4-sysroot/lib/.../libc.so.6 існує на хості
    # і linker відкриває його напряму — отримуємо символи цільової GLIBC.
    set(_script "${lib_dir}/${script_name}")
    set(_content "GROUP ( ${_found} )\n")
    if(EXISTS "${_script}")
        file(READ "${_script}" _existing)
        if(_existing STREQUAL _content)
            return()
        endif()
    endif()

    file(WRITE "${_script}" "${_content}")
    message(STATUS "[Common] Створено ${_script} → ${_found}")
endfunction()

# Спеціальний хелпер для libc.so: включає libc_nonshared.a і ld-linux (AS_NEEDED),
# точно як реальний Debian/Ubuntu linker script /usr/lib/<arch>/libc.so.
function(_ep_write_libc_script lib_dir)
    if(NOT CMAKE_LIBRARY_ARCHITECTURE)
        message(WARNING "[Common] CMAKE_LIBRARY_ARCHITECTURE не встановлено — libc.so не створено.")
        return()
    endif()

    # libc.so.6
    set(_libc_so "")
    foreach(_d "lib" "usr/lib")
        set(_c "${CMAKE_SYSROOT}/${_d}/${CMAKE_LIBRARY_ARCHITECTURE}/libc.so.6")
        if(EXISTS "${_c}")
            set(_libc_so "${_c}")
            break()
        endif()
    endforeach()
    if(NOT _libc_so)
        message(WARNING "[Common] libc.so.6 не знайдено у sysroot — libc.so не створено.")
        return()
    endif()

    # libc_nonshared.a (зазвичай в /usr/lib/<arch>/)
    set(_nonshared "")
    foreach(_d "usr/lib" "lib")
        set(_c "${CMAKE_SYSROOT}/${_d}/${CMAKE_LIBRARY_ARCHITECTURE}/libc_nonshared.a")
        if(EXISTS "${_c}")
            set(_nonshared "${_c}")
            break()
        endif()
    endforeach()

    # ld-linux (AS_NEEDED — не завжди потрібен, але входить до канонічного script)
    set(_ldso "")
    foreach(_d "lib" "usr/lib")
        foreach(_n
                "ld-linux-aarch64.so.1"
                "ld-linux-armhf.so.3"
                "ld-linux-arm.so.3"
                "ld-linux-x86-64.so.2"
                "ld-linux.so.2")
            set(_c "${CMAKE_SYSROOT}/${_d}/${CMAKE_LIBRARY_ARCHITECTURE}/${_n}")
            if(EXISTS "${_c}")
                set(_ldso "${_c}")
                break()
            endif()
        endforeach()
        if(_ldso)
            break()
        endif()
    endforeach()

    # Будуємо GROUP ( libc.so.6 [nonshared] [AS_NEEDED ( ldso )] )
    set(_group "${_libc_so}")
    if(_nonshared)
        string(APPEND _group " ${_nonshared}")
    endif()
    if(_ldso)
        string(APPEND _group " AS_NEEDED ( ${_ldso} )")
    endif()

    set(_script "${lib_dir}/libc.so")
    set(_content "GROUP ( ${_group} )\n")
    if(EXISTS "${_script}")
        file(READ "${_script}" _existing)
        if(_existing STREQUAL _content)
            return()
        endif()
    endif()

    file(WRITE "${_script}" "${_content}")
    if(_nonshared)
        message(STATUS "[Common] Створено ${_script} → ${_libc_so} + libc_nonshared.a")
    else()
        message(STATUS "[Common] Створено ${_script} → ${_libc_so}")
    endif()
endfunction()

function(_ep_create_sysroot_lib_scripts)
    if(NOT CMAKE_CROSSCOMPILING OR NOT CMAKE_SYSROOT)
        return()
    endif()

    set(_lib_dir "${EXTERNAL_INSTALL_PREFIX}/lib")
    file(MAKE_DIRECTORY "${_lib_dir}")

    _ep_write_sysroot_lib_script("${_lib_dir}" libm.so      libm.so.6)
    _ep_write_sysroot_lib_script("${_lib_dir}" libstdc++.so libstdc++.so.6)
    _ep_write_libc_script("${_lib_dir}")
endfunction()

_ep_create_sysroot_lib_scripts()

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

option(EP_LTO
    "Увімкнути Link-Time Optimization при збірці сторонніх бібліотек"
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
        # Крос-компіляція: бібліотеки/заголовки/пакети — тільки в sysroot
        # (через ONLY-режим, який трансформує всі шляхи через CMAKE_FIND_ROOT_PATH).
        # Програми (ninja, python тощо) — на хості (NEVER не застосовує sysroot-prefix).
        #
        # CMAKE_FIND_USE_CMAKE_SYSTEM_PATH і CMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH
        # НЕ відключаємо: ONLY-режим вже ізолює пошук від хост-системи, а ці флаги
        # потрібні щоб CMake генерував sysroot-версії системних шляхів (зокрема
        # multi-arch підпапки /usr/lib/<triplet>/).
        set(${out_var}
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

    # RPi toolchain prefix — критично для sub-projects: toolchain file
    # перечитується і cross_toolchain_find_compiler з FORCE перекриває
    # CMAKE_C/CXX_COMPILER якщо PREFIX не переданий явно.
    foreach(_rpi_prefix_var RPI4_TOOLCHAIN_PREFIX RPI4_GCC_VERSION
                            RPI5_TOOLCHAIN_PREFIX RPI5_GCC_VERSION)
        if(DEFINED ${_rpi_prefix_var})
            list(APPEND _args "-D${_rpi_prefix_var}=${${_rpi_prefix_var}}")
        endif()
    endforeach()

    # Sysroot
    if(CMAKE_SYSROOT)
        list(APPEND _args -DCMAKE_SYSROOT=${CMAKE_SYSROOT})
    endif()
    if(CMAKE_FIND_ROOT_PATH)
        # ExternalProject передає CMAKE_ARGS як cmake-список, де `;` — роздільник.
        # Тому CMAKE_FIND_ROOT_PATH (список шляхів через `;`) не можна передати напряму:
        # ExternalProject розіб'є значення і sysroot-частина потрапляє як позиційний аргумент.
        # Рішення: записуємо значення у cmake init-cache файл і передаємо через -C.
        file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/_ep_cfg")
        set(_ep_frp_file "${CMAKE_BINARY_DIR}/_ep_cfg/ep_find_root_path.cmake")
        file(WRITE "${_ep_frp_file}"
            "set(CMAKE_FIND_ROOT_PATH \"${CMAKE_FIND_ROOT_PATH}\" CACHE STRING \"\" FORCE)\n")
        list(APPEND _args -C "${_ep_frp_file}")
        unset(_ep_frp_file)
    endif()
    if(RPI_SYSROOT)
        list(APPEND _args -DRPI_SYSROOT=${RPI_SYSROOT})
    endif()
    if(YOCTO_SDK_SYSROOT)
        list(APPEND _args -DYOCTO_SDK_SYSROOT=${YOCTO_SDK_SYSROOT})
    endif()

    # Make-програма (ninja/make) — передаємо явно, бо CMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=OFF
    # блокує автоматичний пошук ninja у дочірніх cmake-процесах
    if(CMAKE_MAKE_PROGRAM)
        list(APPEND _args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
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

    # Лінкерний пошуковий шлях: -L для явних залежностей + -rpath-link для
    # транзитивних DT_NEEDED.  GNU ld НЕ використовує -L для DT_NEEDED scanning;
    # натомість він шукає тільки в -rpath-link → -rpath → системних шляхах.
    # Тому обидві директорії (наш prefix і sysroot multiarch) потрібні в rpath-link.
    # Додатково передаємо батьківські CMAKE_*_LINKER_FLAGS щоб зберегти прапори
    # встановлені toolchain (напр. multiarch -L шляхи для Debian sysroot).
    set(_ep_linker_prefix
        "-L${EXTERNAL_INSTALL_PREFIX}/lib"
        # rpath-link: наші артефакти (libtiff, libpng, libjpeg тощо)
        "-Wl,-rpath-link,${EXTERNAL_INSTALL_PREFIX}/lib")
    string(JOIN " " _ep_linker_prefix ${_ep_linker_prefix})
    # RPI_SYSROOT_MULTIARCH встановлюється ВИКЛЮЧНО в RaspberryPi4.cmake і тільки
    # коли toolchain prefix (напр. aarch64-unknown-linux-gnu для CT-NG) відрізняється
    # від multiarch-триплета sysroot (aarch64-linux-gnu у Debian).
    # RaspberryPi5.cmake і нативні toolchain цю змінну НЕ встановлюють.
    if(RPI_SYSROOT_MULTIARCH)
        # rpath-link: sysroot multiarch (libz.so.1, libpthread.so тощо)
        string(APPEND _ep_linker_prefix
            " -Wl,-rpath-link,${CMAKE_SYSROOT}/lib/${RPI_SYSROOT_MULTIARCH}"
            " -Wl,-rpath-link,${CMAKE_SYSROOT}/usr/lib/${RPI_SYSROOT_MULTIARCH}")
    endif()
    list(APPEND _args
        "-DCMAKE_SHARED_LINKER_FLAGS=${_ep_linker_prefix} ${CMAKE_SHARED_LINKER_FLAGS}"
        "-DCMAKE_EXE_LINKER_FLAGS=${_ep_linker_prefix} ${CMAKE_EXE_LINKER_FLAGS}"
    )

    # RPATH
    if(USE_ORIGIN_RPATH)
        list(APPEND _args
            "-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib"
            -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
            -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
        )
    endif()

    # LTO для EP-бібліотек
    if(EP_LTO)
        list(APPEND _args
            -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON
            -DCMAKE_POLICY_DEFAULT_CMP0069=NEW)
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
    file(MAKE_DIRECTORY "${inc_dir}")
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
    file(MAKE_DIRECTORY "${inc_dir}")
    add_library(${target} INTERFACE IMPORTED GLOBAL)
    set_target_properties(${target} PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${inc_dir}"
    )
endfunction()

# ---------------------------------------------------------------------------
# _ep_make_sync_target(<ep_name>)
#
# Внутрішня функція. Створює non-IMPORTED INTERFACE-бібліотеку
# _ep_sync_<ep_name> — носій залежності від EP для споживачів.
#
# Проблема: add_dependencies(IMPORTED_target ep) НЕ поширюється через
# target_link_libraries на споживачів — їхні compile/link кроки не чекають EP.
# Рішення: non-IMPORTED INTERFACE-бібліотека в INTERFACE_LINK_LIBRARIES
# пропагується через target_link_libraries і CMake включає її utility-deps
# (тобто залежність від EP) в ORDER_ONLY для compile і link кроків споживача.
# ---------------------------------------------------------------------------
function(_ep_make_sync_target ep_name)
    set(_sync _ep_sync_${ep_name})
    if(NOT TARGET ${_sync})
        add_library(${_sync} INTERFACE)
        add_dependencies(${_sync} ${ep_name})
        # Register so ep_target_add_compile_deps can depend directly on the
        # real EP custom target without traversing INTERFACE_LINK_LIBRARIES.
        set_property(GLOBAL APPEND PROPERTY _EP_BUILD_TARGETS "${ep_name}")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# ep_imported_library_from_ep(<target> <ep_name> <lib_path> <inc_dir>)
#
# Як ep_imported_library, але з залежністю від ExternalProject.
# Виклик ПІСЛЯ ExternalProject_Add.
# ---------------------------------------------------------------------------
function(ep_imported_library_from_ep target ep_name lib_path inc_dir)
    ep_imported_library(${target} "${lib_path}" "${inc_dir}")
    _ep_make_sync_target(${ep_name})
    set_property(TARGET ${target} APPEND PROPERTY
        INTERFACE_LINK_LIBRARIES _ep_sync_${ep_name})
endfunction()

# ---------------------------------------------------------------------------
# ep_imported_interface_from_ep(<target> <ep_name> <inc_dir>)
#
# Як ep_imported_interface, але з залежністю від ExternalProject.
# ---------------------------------------------------------------------------
function(ep_imported_interface_from_ep target ep_name inc_dir)
    ep_imported_interface(${target} "${inc_dir}")
    _ep_make_sync_target(${ep_name})
    set_property(TARGET ${target} APPEND PROPERTY
        INTERFACE_LINK_LIBRARIES _ep_sync_${ep_name})
endfunction()

# ---------------------------------------------------------------------------
# ep_target_add_compile_deps(<target>)
#
# Явна ORDER_ONLY залежність compile-кроків <target> на ExternalProject цілі.
#
# Причина: CMake НЕ propagates utility-deps з INTERFACE_LINK_LIBRARIES
# IMPORTED-таргетів на compile-кроки споживача. Ninja починає компіляцію
# до того як EP встановив заголовки і бібліотеки.
#
# Ключовий факт: add_dependencies(A B) впливає на cmake_object_order_depends_target
# тільки якщо B — реальна CMake ціль (add_custom_target або executable/library),
# але НЕ INTERFACE-бібліотека. _ep_sync_* є INTERFACE — тому ігнорується.
# Тому залежимо напряму від реального EP (add_custom_target від ExternalProject_Add),
# чиї імена реєструє _ep_make_sync_target у глобальній властивості _EP_BUILD_TARGETS.
# Якщо EP вже встановлено (find_package знайшов) — ExternalProject_Add не викликається,
# _ep_make_sync_target не викликається, реєстр порожній — compile просто йде без блокування.
#
# Використання:
#   target_link_libraries(my_app PRIVATE OpenCV::opencv_core ...)
#   ep_target_add_compile_deps(my_app)
# ---------------------------------------------------------------------------
function(ep_target_add_compile_deps main_target)
    # Read the registry populated by _ep_make_sync_target at configuration time.
    # The registry only contains EPs that are actually being built (i.e.
    # ExternalProject_Add fired). When a library is already installed and
    # find_package succeeds, _ep_make_sync_target is never called, the EP
    # custom target doesn't exist, and there's nothing to wait for — correct.
    get_property(_ep_targets GLOBAL PROPERTY _EP_BUILD_TARGETS)
    foreach(_ep IN LISTS _ep_targets)
        if(TARGET "${_ep}")
            add_dependencies("${main_target}" "${_ep}")
        endif()
    endforeach()
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

function(_ep_collect_deps_install out_var)
    set(_existing "")
    foreach(_ep ${ARGN})
        if(TARGET ${_ep})
            list(APPEND _existing ${_ep}-install)
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
# ep_prestamp_git(<ep_name> <source_dir> <git_tag>)
#
# Якщо SOURCE_DIR вже містить git-репозиторій з потрібним тегом/комітом,
# попередньо створює download stamp щоб ExternalProject пропустив git fetch
# при наступній збірці після видалення build-директорії (зі збереженням сорців).
#
# Без цього ExternalProject завжди виконує git fetch навіть якщо репозиторій
# вже актуальний, що уповільнює збірку та потребує мережі.
#
# Виклик: після ExternalProject_Add у кожному Lib*.cmake
#   ep_prestamp_git(libcamera_ep "${EP_SOURCES_DIR}/libcamera" "v0.5.2+rpt20250903")
#
# Ідемпотентна: якщо stamp вже існує — нічого не робить.
# ---------------------------------------------------------------------------
function(ep_prestamp_git ep_name source_dir git_tag)
    if(NOT EXISTS "${source_dir}/.git")
        return()
    endif()
    # Перевіряємо поточний тег/коміт через git describe
    execute_process(
        COMMAND git describe --tags --exact-match HEAD
        WORKING_DIRECTORY "${source_dir}"
        OUTPUT_VARIABLE _current_tag
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    # Також перевіряємо через git rev-parse (для тегів що не є annotated)
    if(NOT _current_tag STREQUAL git_tag)
        execute_process(
            COMMAND git log -1 --format=%D HEAD
            WORKING_DIRECTORY "${source_dir}"
            OUTPUT_VARIABLE _current_refs
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(NOT _current_refs MATCHES "${git_tag}")
            return()  # Не той тег — нехай ExternalProject оновить
        endif()
    endif()
    set(_stamp_dir "${CMAKE_BINARY_DIR}/${ep_name}-prefix/src/${ep_name}-stamp")
    set(_dl_stamp  "${_stamp_dir}/${ep_name}-download")
    if(NOT EXISTS "${_dl_stamp}")
        file(MAKE_DIRECTORY "${_stamp_dir}")
        file(WRITE "${_dl_stamp}" "")
        message(STATUS "[${ep_name}] Джерела вже на тегу ${git_tag} — download stamp (пропуск fetch)")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# ep_track_cmake_file(<ep_name> <cmake_file>)
#
# Змушує ExternalProject перезапустити configure (і відповідно rebuild) коли
# змінюється Lib*.cmake файл конфігурації бібліотеки.
#
# ВАЖЛИВО: cmake_file МУСИТЬ передаватися явно як "${CMAKE_CURRENT_LIST_FILE}"
# з місця виклику (Lib*.cmake). Всередині функції CMAKE_CURRENT_LIST_FILE
# вказує на Common.cmake (поведінка CMake 3.17+).
#
# Також створює два допоміжні таргети:
#
#   <ep_name>-reset    — видаляє ВСІ stamp-файли (download + configure + build + install).
#                        Використовувати після помилки завантаження або при зміні
#                        cmake-аргументів EP.
#
#   <ep_name>-rebuild  — видаляє тільки configure + build + install стампи.
#                        download пропускається — сорці вже є.
#                        Використовувати після ручної правки файлів у EP_SOURCES_DIR
#                        (наприклад, додали логування до OpenCV).
#
# Виклик: після ExternalProject_Add у кожному Lib*.cmake
#   ep_track_cmake_file(libcamera_ep "${CMAKE_CURRENT_LIST_FILE}")
#
# Workflow після зміни сорців:
#   cmake --build <build_dir> --target opencv_ep-rebuild
#   cmake --build <build_dir>
# ---------------------------------------------------------------------------
function(ep_track_cmake_file ep_name cmake_file)
    ExternalProject_Add_Step(${ep_name} reconfigure_on_cmake_change
        DEPENDERS configure
        DEPENDS   "${cmake_file}"
    )
    ExternalProject_Get_Property(${ep_name} stamp_dir)
    add_custom_target(${ep_name}-reset
        COMMAND ${CMAKE_COMMAND} -E remove_directory "${stamp_dir}"
        COMMENT "[${ep_name}] Всі stamp-файли видалено — наступний build перезапустить всі кроки"
        VERBATIM
    )
    add_custom_target(${ep_name}-rebuild
        COMMAND ${CMAKE_COMMAND} -E rm -f
            "${stamp_dir}/${ep_name}-configure"
            "${stamp_dir}/${ep_name}-build"
            "${stamp_dir}/${ep_name}-install"
        COMMENT "[${ep_name}] Configure+build+install stamps видалено — наступний build перекомпілює сорці"
        VERBATIM
    )
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

    # Рядки для секцій cross-файлу
    set(_mc_properties_section "")
    set(_mc_builtin_options_section "")

    # [properties]: pkg_config_libdir — EXTERNAL_INSTALL_PREFIX завжди першим,
    # щоб наші зібрані бібліотеки мали пріоритет над sysroot.
    # При крос-компіляції meson ІГНОРУЄ PKG_CONFIG_PATH з env і використовує
    # ВИКЛЮЧНО pkg_config_libdir з cross-файлу.
    set(_mc_pkgconfig_paths
        "${EXTERNAL_INSTALL_PREFIX}/lib/pkgconfig"
        "${EXTERNAL_INSTALL_PREFIX}/share/pkgconfig"
    )
    if(CMAKE_SYSROOT)
        # Додаємо sysroot після наших артефактів.
        # НЕ використовуємо sys_root — meson 1.x некоректно застосовує його:
        # додає sysroot-префікс до -I шляхів з cpp_args замість того щоб передати
        # --sysroot компілятору. Sysroot передаємо через [built-in options].
        #
        # Включаємо multiarch підпапку (/usr/lib/<triplet>/pkgconfig), якщо відома
        # (CMAKE_LIBRARY_ARCHITECTURE задається cmake на основі виводу компілятора).
        list(APPEND _mc_pkgconfig_paths
            "${CMAKE_SYSROOT}/usr/lib/pkgconfig"
            "${CMAKE_SYSROOT}/usr/share/pkgconfig"
            "${CMAKE_SYSROOT}/lib/pkgconfig"
        )
        if(CMAKE_LIBRARY_ARCHITECTURE)
            list(APPEND _mc_pkgconfig_paths
                "${CMAKE_SYSROOT}/usr/lib/${CMAKE_LIBRARY_ARCHITECTURE}/pkgconfig"
                "${CMAKE_SYSROOT}/lib/${CMAKE_LIBRARY_ARCHITECTURE}/pkgconfig"
            )
        endif()
    endif()
    string(JOIN ":" _mc_pkgconfig_str ${_mc_pkgconfig_paths})
    string(APPEND _mc_properties_section
        "pkg_config_libdir = '${_mc_pkgconfig_str}'\n")
    unset(_mc_pkgconfig_paths)
    unset(_mc_pkgconfig_str)

    # [built-in options] для ГОЛОВНОГО cross-файлу:
    # - c_args/cpp_args: тільки --sysroot (без -I).
    #   Meson 1.3.x не передає -I з cpp_args до compile команд коли в тому ж масиві є --sysroot.
    #   Тому -I розміщується у ОКРЕМОМУ cross-файлі (meson-cross-paths.ini), який meson
    #   обробляє незалежно і результат мержить. Meson merges arrays from multiple --cross-file.
    # - c_link_args/cpp_link_args: --sysroot + -L (обидва флаги передаються коректно для лінкера).
    # Конвертуємо EP_EXTRA_CFLAGS/LDFLAGS (пробіл-розділені) → рядок meson-масиву
    # Приклад: "-mcpu=cortex-a72 -O2" → "'-mcpu=cortex-a72', '-O2'"
    set(_mc_extra_cflags_str "")
    set(_mc_extra_ldflags_str "")
    if(EP_EXTRA_CFLAGS)
        separate_arguments(_mc_extra_cflags_list UNIX_COMMAND "${EP_EXTRA_CFLAGS}")
        foreach(_f IN LISTS _mc_extra_cflags_list)
            string(APPEND _mc_extra_cflags_str ", '${_f}'")
        endforeach()
        unset(_mc_extra_cflags_list)
    endif()
    if(EP_EXTRA_LDFLAGS)
        separate_arguments(_mc_extra_ldflags_list UNIX_COMMAND "${EP_EXTRA_LDFLAGS}")
        foreach(_f IN LISTS _mc_extra_ldflags_list)
            string(APPEND _mc_extra_ldflags_str ", '${_f}'")
        endforeach()
        unset(_mc_extra_ldflags_list)
    endif()

    # c_std = 'c11': GCC для C файлів у gnu17 (або не-explicit) mode автоматично
    # передає -D_GNU_SOURCE що через features.h вмикає __GLIBC_USE_C2X_STRTOL=1
    # і ремапить strtoul → __isoc23_strtoul@GLIBC_2.38. Strict c11 (без gnu) не
    # додає -D_GNU_SOURCE → ремапінгу немає. Це базова вимога для крос-компіляції
    # під target glibc < 2.38.
    # cpp_std = 'c++20': для C++ -D_GNU_SOURCE завжди є (незалежно від стандарту);
    # fix для C++ — через preamble у cpp_args (meson-cross-paths.ini). Тут c++20
    # встановлюється як проєктний стандарт за замовченням.
    string(APPEND _mc_builtin_options_section "c_std = 'c11'\ncpp_std = 'c++20'\n")

    if(CMAKE_SYSROOT)
        string(APPEND _mc_builtin_options_section
            "c_args = ['--sysroot=${CMAKE_SYSROOT}']\n"
            "cpp_args = ['--sysroot=${CMAKE_SYSROOT}']\n"
            "c_link_args = ['--sysroot=${CMAKE_SYSROOT}', '-L${EXTERNAL_INSTALL_PREFIX}/lib']\n"
            "cpp_link_args = ['--sysroot=${CMAKE_SYSROOT}', '-L${EXTERNAL_INSTALL_PREFIX}/lib']\n")
    else()
        string(APPEND _mc_builtin_options_section
            "c_args = ['-I${EXTERNAL_INSTALL_PREFIX}/include'${_mc_extra_cflags_str}]\n"
            "cpp_args = ['-I${EXTERNAL_INSTALL_PREFIX}/include'${_mc_extra_cflags_str}]\n"
            "c_link_args = ['-L${EXTERNAL_INSTALL_PREFIX}/lib'${_mc_extra_ldflags_str}]\n"
            "cpp_link_args = ['-L${EXTERNAL_INSTALL_PREFIX}/lib'${_mc_extra_ldflags_str}]\n")
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
${_mc_properties_section}
[built-in options]
${_mc_builtin_options_section}
[host_machine]
system = 'linux'
cpu_family = '${_meson_cpu_family}'
cpu = '${_meson_cpu_family}'
endian = 'little'
")

    # При крос-компіляції з sysroot: генеруємо ДРУГИЙ cross-файл (meson-cross-paths.ini).
    #
    # Поведінка meson з кількома --cross-file (перевірено на 1.10.x):
    #   Файли обробляються від останнього до першого; перший знайдений ключ виграє.
    #   Тобто ОСТАННІЙ вказаний файл має пріоритет над попередніми.
    #   Для list-типів (c_args тощо) — НЕ мержить, останній файл перезаписує.
    #
    # Тому paths-файл (останній) мусить містити ВСЕ: --sysroot, -I, -L та multiarch.
    # Головний cross-файл (перший) містить --sysroot/-L лише як fallback для non-paths
    # варіантів (нативна збірка без CMAKE_SYSROOT — тоді paths-файл не генерується).
    set(_cross_args "--cross-file" "${_cross_file}")
    if(CMAKE_SYSROOT)
        set(_cross_paths_file "${CMAKE_BINARY_DIR}/_ep_cfg/meson-cross-paths.ini")

        # c_args: --sysroot обов'язковий (інакше GCC використовує вбудований sysroot CT-NG)
        # + наші артефакти -I + toolchain-специфічні прапори (EP_EXTRA_CFLAGS)
        set(_mcp_c_args "'--sysroot=${CMAKE_SYSROOT}', '-I${EXTERNAL_INSTALL_PREFIX}/include'${_mc_extra_cflags_str}")
        # c_link_args: --sysroot + наші артефакти -L + -rpath-link для DT_NEEDED
        # GNU ld не використовує -L для DT_NEEDED scanning → потрібен -rpath-link
        # для нашого prefix щоб лінкер знаходив libtiff.so.6, libpng.so тощо.
        # + toolchain-специфічні лінкер прапори (EP_EXTRA_LDFLAGS)
        set(_mcp_link_args
            "'--sysroot=${CMAKE_SYSROOT}', '-L${EXTERNAL_INSTALL_PREFIX}/lib', '-Wl,-rpath-link,${EXTERNAL_INSTALL_PREFIX}/lib'${_mc_extra_ldflags_str}")

        # CT-NG toolchain: коли multiarch-триплет sysroot відрізняється від
        # toolchain prefix, потрібні додаткові include/lib шляхи.
        # RPI_SYSROOT_MULTIARCH встановлюється тільки в цьому випадку →
        # Ubuntu build (де триплети збігаються) цього блоку не виконує.
        # RPI_SYSROOT_MULTIARCH: встановлюється тільки RaspberryPi4.cmake (CT-NG сценарій).
        # RaspberryPi5.cmake та Ubuntu build цю змінну не отримують → блок не виконується.
        if(RPI_SYSROOT_MULTIARCH)
            # CT-NG: toolchain prefix відрізняється від multiarch-триплета sysroot.
            # -isystem: GCC не знає про /usr/include/<multiarch>/ в sysroot автоматично.
            # -B: GCC-driver знаходить startup-файли (crt1.o, crti.o) у multiarch-директорії.
            #     Без цього meson link-тести падають: "cannot find crt1.o".
            # -L: лінкер знаходить libc.so.6 тощо.
            # -Wl,-rpath-link: лінкер знаходить транзитивні залежності .so (libz → libtiff).
            #   -L дозволяє пряме лінкування, але -rpath-link потрібен для DT_NEEDED
            #   при крос-компіляції де рантайм шляхи відрізняються.
            string(APPEND _mcp_c_args
                ", '-isystem${CMAKE_SYSROOT}/usr/include/${RPI_SYSROOT_MULTIARCH}'")
            string(APPEND _mcp_link_args
                ", '-B${CMAKE_SYSROOT}/lib/${RPI_SYSROOT_MULTIARCH}'"
                ", '-B${CMAKE_SYSROOT}/usr/lib/${RPI_SYSROOT_MULTIARCH}'"
                ", '-L${CMAKE_SYSROOT}/lib/${RPI_SYSROOT_MULTIARCH}'"
                ", '-L${CMAKE_SYSROOT}/usr/lib/${RPI_SYSROOT_MULTIARCH}'"
                ", '-Wl,-rpath-link,${CMAKE_SYSROOT}/lib/${RPI_SYSROOT_MULTIARCH}'"
                ", '-Wl,-rpath-link,${CMAKE_SYSROOT}/usr/lib/${RPI_SYSROOT_MULTIARCH}'")
        endif()

        # C++ preamble: виправляє ремапінг strtoul → __isoc23_strtoul@GLIBC_2.38.
        #
        # Проблема: aarch64-linux-gnu-g++ на Ubuntu 24.04 завжди передає -D_GNU_SOURCE
        # до cc1plus (з spec-файлу компілятора). _GNU_SOURCE → _ISOC2X_SOURCE=1 →
        # __GLIBC_USE_C2X_STRTOL=1 → stdlib.h ремапує strtoul → __isoc23_strtoul.
        # Цей символ відсутній у glibc < 2.38 (Raspberry Pi OS, старі Yocto sysroot).
        # -std=c++20 або -D__GLIBC_USE_C2X_STRTOL=0 не допомагають: features.h
        # завжди #undef і перевизначає __GLIBC_USE_C2X_STRTOL після наших -D.
        #
        # Рішення (preamble trick): -include цього файлу → він включає <features.h>
        # першим і виставляє include guard _FEATURES_H. Потім ми #undef/#define
        # __GLIBC_USE_C2X_STRTOL=0. Усі подальші #include <features.h> (через
        # stdlib.h, cstdlib тощо) — no-op через guard. Результат: strtoul
        # компілюється як стандартний POSIX strtoul без asm-alias.
        set(_mcp_preamble "${CMAKE_BINARY_DIR}/_ep_cfg/meson-cpp-preamble.h")
        file(WRITE "${_mcp_preamble}"
"/* Auto-generated: prevent Ubuntu 24.04 cross-compiler glibc C23 strtoul remapping.
 * aarch64-linux-gnu-g++ spec auto-adds -D_GNU_SOURCE which via features.h enables
 * __GLIBC_USE_C2X_STRTOL=1, remapping strtoul -> __isoc23_strtoul@GLIBC_2.38.
 * That symbol is absent in target glibc < 2.38.  Fix: force features.h include guard
 * before stdlib.h / cstdlib, then lock __GLIBC_USE_C2X_STRTOL to 0. */
#include <features.h>
#undef  __GLIBC_USE_C2X_STRTOL
#define __GLIBC_USE_C2X_STRTOL 0
")
        set(_mcp_cpp_args "${_mcp_c_args}, '-include${_mcp_preamble}'")

        file(WRITE "${_cross_paths_file}"
"[built-in options]
c_args = [${_mcp_c_args}]
cpp_args = [${_mcp_cpp_args}]
c_link_args = [${_mcp_link_args}]
cpp_link_args = [${_mcp_link_args}]
")
        list(APPEND _cross_args "--cross-file" "${_cross_paths_file}")

        # Виставляємо рядки аргументів у PARENT_SCOPE для використання в overlay-файлах.
        # Бібліотека може мати свій overlay з додатковими cpp_args (напр. -Wno-error=...).
        # Щоб overlay не перезаписав --sysroot/-I/-L/-include, він мусить містити ВСІ flags.
        # MESON_CROSS_C_ARGS   — для C файлів (без preamble)
        # MESON_CROSS_CXX_ARGS — для C++ файлів (з preamble)
        set(MESON_CROSS_C_ARGS     "${_mcp_c_args}"   PARENT_SCOPE)
        set(MESON_CROSS_CXX_ARGS   "${_mcp_cpp_args}" PARENT_SCOPE)
        set(MESON_CROSS_LINK_ARGS  "${_mcp_link_args}" PARENT_SCOPE)

        unset(_mcp_c_args)
        unset(_mcp_cpp_args)
        unset(_mcp_link_args)
        unset(_mcp_preamble)
    else()
        # Без sysroot — очищаємо (нативна збірка)
        set(MESON_CROSS_C_ARGS    "" PARENT_SCOPE)
        set(MESON_CROSS_CXX_ARGS  "" PARENT_SCOPE)
        set(MESON_CROSS_LINK_ARGS "" PARENT_SCOPE)
    endif()

    unset(_mc_extra_cflags_str)
    unset(_mc_extra_ldflags_str)
    set(${out_var} ${_cross_args} PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# _meson_write_overlay(<ep_name> <in_out_args_var> [EXTRA_CXX <flag> ...])
#
# Записує overlay-файл _ep_cfg/meson-<ep_name>-overlay.ini і додає
# --native-file або --cross-file до <in_out_args_var>.
#
# Overlay завжди містить:
#   cpp_args = ['-I${EXTERNAL_INSTALL_PREFIX}/include', <EXTRA_CXX>...]
# У режимі крос-компіляції додатково:
#   cpp_args  містить MESON_CROSS_CXX_ARGS (preamble з Common.cmake)
#   c_args    = [MESON_CROSS_C_ARGS]
#   c_link_args / cpp_link_args = [MESON_CROSS_LINK_ARGS]
#
# ВАЖЛИВО: meson бере [built-in options] з останнього --cross-file/--native-file,
# тому overlay мусить перераховувати ВСІ cpp_args, а не лише нові.
# ---------------------------------------------------------------------------
function(_meson_write_overlay ep_name in_out_args_var)
    # Розбираємо EXTRA_CXX ...
    cmake_parse_arguments(_OV "" "" "EXTRA_CXX" ${ARGN})

    # Формуємо рядок додаткових прапорів у форматі meson-списку
    set(_extra_cxx_str "")
    foreach(_f ${_OV_EXTRA_CXX})
        string(APPEND _extra_cxx_str ", '${_f}'")
    endforeach()

    set(_overlay_file "${CMAKE_BINARY_DIR}/_ep_cfg/meson-${ep_name}-overlay.ini")

    if(CMAKE_CROSSCOMPILING)
        file(WRITE "${_overlay_file}"
            "[built-in options]\n"
            "cpp_args = [${MESON_CROSS_CXX_ARGS}, '-I${EXTERNAL_INSTALL_PREFIX}/include'${_extra_cxx_str}]\n"
            "c_args = [${MESON_CROSS_C_ARGS}]\n"
            "c_link_args = [${MESON_CROSS_LINK_ARGS}]\n"
            "cpp_link_args = [${MESON_CROSS_LINK_ARGS}]\n")
        list(APPEND ${in_out_args_var} "--cross-file" "${_overlay_file}")
    else()
        file(WRITE "${_overlay_file}"
            "[built-in options]\n"
            "cpp_args = ['-I${EXTERNAL_INSTALL_PREFIX}/include'${_extra_cxx_str}]\n")
        list(APPEND ${in_out_args_var} "--native-file" "${_overlay_file}")
    endif()

    set(${in_out_args_var} ${${in_out_args_var}} PARENT_SCOPE)
    unset(_extra_cxx_str)
    unset(_overlay_file)
endfunction()
