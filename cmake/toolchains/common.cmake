# cmake/toolchains/common.cmake
#
# Спільні утиліти для всіх toolchain файлів.
# Підключається через include() на початку кожного toolchain.
#
# Використання:
#   include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

cmake_minimum_required(VERSION 3.28)

# ---------------------------------------------------------------------------
# cross_toolchain_find_compiler
#
# Шукає компілятор за префіксом. При невдачі видає зрозуміле повідомлення
# з інструкцією з встановлення.
#
# Аргументи:
#   PREFIX   — префікс тулчейну (напр. aarch64-linux-gnu)
#   INSTALL  — пакет для встановлення (напр. gcc-aarch64-linux-gnu)
# ---------------------------------------------------------------------------
macro(cross_toolchain_find_compiler PREFIX INSTALL)
    find_program(_CC  "${PREFIX}-gcc"  HINTS ENV PATH)
    find_program(_CXX "${PREFIX}-g++" HINTS ENV PATH)

    if(NOT _CC OR NOT _CXX)
        message(FATAL_ERROR
            "\n[Toolchain] Компілятор '${PREFIX}-gcc' не знайдено.\n"
            "Встановіть пакет командою:\n"
            "  sudo apt install ${INSTALL}\n"
            "Або вкажіть власний префікс через -D${_TOOLCHAIN_PREFIX_VAR}=<prefix>\n")
    endif()

    set(CMAKE_C_COMPILER   "${_CC}"  CACHE FILEPATH "C compiler"   FORCE)
    set(CMAKE_CXX_COMPILER "${_CXX}" CACHE FILEPATH "C++ compiler" FORCE)

    find_program(_AR     "${PREFIX}-ar")
    find_program(_STRIP  "${PREFIX}-strip")
    find_program(_RANLIB "${PREFIX}-ranlib")

    if(_AR)
        set(CMAKE_AR     "${_AR}"     CACHE FILEPATH "Archiver" FORCE)
    endif()
    if(_STRIP)
        set(CMAKE_STRIP  "${_STRIP}"  CACHE FILEPATH "Strip"    FORCE)
    endif()
    if(_RANLIB)
        set(CMAKE_RANLIB "${_RANLIB}" CACHE FILEPATH "Ranlib"   FORCE)
    endif()

    unset(_CC)
    unset(_CXX)
    unset(_AR)
    unset(_STRIP)
    unset(_RANLIB)
endmacro()

# ---------------------------------------------------------------------------
# cross_toolchain_setup_sysroot
#
# Налаштовує sysroot та режими пошуку бібліотек.
# Викликати після встановлення CMAKE_SYSROOT.
# ---------------------------------------------------------------------------
macro(cross_toolchain_setup_sysroot)
    # Програми (cmake, python тощо) завжди беремо з хост-системи
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    # Бібліотеки, заголовки та пакети — тільки з sysroot
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
endmacro()

# ---------------------------------------------------------------------------
# cross_toolchain_no_sysroot
#
# Режим без sysroot: нативна збірка або збірка без прив'язки до конкретного
# образу цільової системи.
# ---------------------------------------------------------------------------
macro(cross_toolchain_no_sysroot)
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BOTH)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
endmacro()

# ---------------------------------------------------------------------------
# cross_toolchain_find_versioned_native_gcc
#
# Шукає версований native GCC (gcc-N / g++-N) та LTO-утиліти (gcc-ar/ranlib/nm).
# При невдачі видає FATAL_ERROR з порадою щодо встановлення.
#
# Аргументи:
#   VERSION     — версія GCC (напр. "13")
#   VERSION_VAR — ім'я кеш-змінної (для підказки у повідомленні, напр. UBUNTU2404_GCC_VERSION)
# ---------------------------------------------------------------------------
macro(cross_toolchain_find_versioned_native_gcc VERSION VERSION_VAR)
    find_program(CMAKE_C_COMPILER   "gcc-${VERSION}")
    find_program(CMAKE_CXX_COMPILER "g++-${VERSION}")
    if(NOT CMAKE_C_COMPILER OR NOT CMAKE_CXX_COMPILER)
        message(FATAL_ERROR
            "\n[Toolchain] GCC ${VERSION} не знайдено.\n"
            "Встановіть: sudo apt install gcc-${VERSION} g++-${VERSION}\n"
            "Або вкажіть іншу версію: -D${VERSION_VAR}=<версія>\n")
    endif()
    set(CMAKE_C_COMPILER   "${CMAKE_C_COMPILER}"   CACHE FILEPATH "C compiler"   FORCE)
    set(CMAKE_CXX_COMPILER "${CMAKE_CXX_COMPILER}" CACHE FILEPATH "C++ compiler" FORCE)
    find_program(_vng_ar     "gcc-ar-${VERSION}")
    find_program(_vng_ranlib "gcc-ranlib-${VERSION}")
    find_program(_vng_nm     "gcc-nm-${VERSION}")
    if(_vng_ar)     set(CMAKE_AR     "${_vng_ar}"     CACHE FILEPATH "Archiver (LTO-aware)"  FORCE) endif()
    if(_vng_ranlib) set(CMAKE_RANLIB "${_vng_ranlib}" CACHE FILEPATH "Ranlib (LTO-aware)"    FORCE) endif()
    if(_vng_nm)     set(CMAKE_NM     "${_vng_nm}"     CACHE FILEPATH "NM (LTO-aware)"        FORCE) endif()
    unset(_vng_ar)
    unset(_vng_ranlib)
    unset(_vng_nm)
endmacro()

# ---------------------------------------------------------------------------
# cross_toolchain_find_versioned_cross_compiler
#
# Шукає версований cross-GCC (<PREFIX>-gcc-<VERSION>) та binutils.
# Встановлює CMAKE_C_COMPILER, CMAKE_CXX_COMPILER, CMAKE_AR/STRIP/RANLIB
# і виставляє <PREFIX>_VERSIONED_FOUND у TRUE/FALSE для caller-logic fallback.
#
# Аргументи:
#   PREFIX  — toolchain prefix (напр. aarch64-linux-gnu)
#   VERSION — версія GCC (напр. "12")
# ---------------------------------------------------------------------------
macro(cross_toolchain_find_versioned_cross_compiler PREFIX VERSION)
    find_program(_vcc_cc  "${PREFIX}-gcc-${VERSION}"  HINTS ENV PATH)
    find_program(_vcc_cxx "${PREFIX}-g++-${VERSION}" HINTS ENV PATH)
    if(_vcc_cc AND _vcc_cxx)
        set(CMAKE_C_COMPILER   "${_vcc_cc}"  CACHE FILEPATH "C compiler"   FORCE)
        set(CMAKE_CXX_COMPILER "${_vcc_cxx}" CACHE FILEPATH "C++ compiler" FORCE)
        find_program(_vcc_ar     "${PREFIX}-ar")
        find_program(_vcc_strip  "${PREFIX}-strip")
        find_program(_vcc_ranlib "${PREFIX}-ranlib")
        if(_vcc_ar)     set(CMAKE_AR     "${_vcc_ar}"     CACHE FILEPATH "Archiver" FORCE) endif()
        if(_vcc_strip)  set(CMAKE_STRIP  "${_vcc_strip}"  CACHE FILEPATH "Strip"    FORCE) endif()
        if(_vcc_ranlib) set(CMAKE_RANLIB "${_vcc_ranlib}" CACHE FILEPATH "Ranlib"   FORCE) endif()
        unset(_vcc_ar)
        unset(_vcc_strip)
        unset(_vcc_ranlib)
        set(_vcc_found TRUE)
    else()
        set(_vcc_found FALSE)
    endif()
    unset(_vcc_cc)
    unset(_vcc_cxx)
endmacro()

# ---------------------------------------------------------------------------
# cross_toolchain_setup_linux_multiarch
#
# Налаштовує Debian multiarch sysroot: додає -L/-B/-isystem прапори для
# коректного лінкування з sysroot що містить бібліотеки у підкаталозі
# lib/<triple>/ (Debian/Ubuntu multiarch layout).
#
# Аргументи:
#   TOOLCHAIN_PREFIX — префікс toolchain (напр. aarch64-linux-gnu)
#   SYSROOT          — шлях до sysroot
#   TOOLCHAIN_NAME   — назва для діагностичних повідомлень (напр. RaspberryPi4)
#   ARGN             — додаткові fallback триплети для автовизначення
#                      (напр. "aarch64-linux-gnu" "aarch64-linux-gnueabi")
#
# Якщо multiarch-триплет відрізняється від TOOLCHAIN_PREFIX — також виставляє
# RPI_SYSROOT_MULTIARCH у кеш (для non-CMake sub-builds: OpenSSL, Meson).
#
# Використання:
#   cross_toolchain_setup_linux_multiarch(
#       "${RPI4_TOOLCHAIN_PREFIX}" "${RPI_SYSROOT}" "RaspberryPi4"
#       "aarch64-linux-gnu" "aarch64-linux-gnueabi")
# ---------------------------------------------------------------------------
macro(cross_toolchain_setup_linux_multiarch TOOLCHAIN_PREFIX SYSROOT TOOLCHAIN_NAME)
    # Auto-detect multiarch triple
    if(IS_DIRECTORY "${SYSROOT}/lib/${TOOLCHAIN_PREFIX}")
        set(_ctslm_multiarch "${TOOLCHAIN_PREFIX}")
    else()
        set(_ctslm_multiarch "")
        foreach(_ctslm_triple ${ARGN})
            if(IS_DIRECTORY "${SYSROOT}/lib/${_ctslm_triple}")
                set(_ctslm_multiarch "${_ctslm_triple}")
                break()
            endif()
        endforeach()
        unset(_ctslm_triple)
        if(NOT _ctslm_multiarch)
            set(_ctslm_multiarch "${TOOLCHAIN_PREFIX}")
            message(WARNING
                "[${TOOLCHAIN_NAME}] Не вдалося визначити multiarch-триплет sysroot, "
                "використовується ${_ctslm_multiarch}")
        else()
            message(STATUS
                "[${TOOLCHAIN_NAME}] Sysroot multiarch: ${_ctslm_multiarch} "
                "(toolchain prefix: ${TOOLCHAIN_PREFIX})")
        endif()
    endif()

    set(_ctslm_lib "${SYSROOT}/lib/${_ctslm_multiarch}")
    set(_ctslm_usr "${SYSROOT}/usr/lib/${_ctslm_multiarch}")

    # -L: лінкер знаходить libc.so.6 та інші розділені бібліотеки
    foreach(_ctslm_fvar
            CMAKE_EXE_LINKER_FLAGS_INIT
            CMAKE_SHARED_LINKER_FLAGS_INIT
            CMAKE_MODULE_LINKER_FLAGS_INIT)
        set(${_ctslm_fvar}
            "-L${_ctslm_lib} -L${_ctslm_usr} ${${_ctslm_fvar}}"
            CACHE INTERNAL "")
    endforeach()
    unset(_ctslm_fvar)

    # -B: потрібен лише коли триплет toolchain ≠ multiarch-триплет sysroot
    # (напр. CT-NG aarch64-unknown-linux-gnu → Debian sysroot aarch64-linux-gnu).
    # -B вказує GCC де шукати startup-файли (crt1.o, crti.o).
    if(NOT _ctslm_multiarch STREQUAL "${TOOLCHAIN_PREFIX}")
        set(_ctslm_extra " -B${_ctslm_lib} -B${_ctslm_usr}")
        foreach(_ctslm_fvar CMAKE_C_FLAGS_INIT CMAKE_CXX_FLAGS_INIT)
            set(${_ctslm_fvar}
                "${${_ctslm_fvar}}${_ctslm_extra}"
                CACHE INTERNAL "")
        endforeach()
        unset(_ctslm_fvar)
        unset(_ctslm_extra)

        # Для non-CMake sub-builds (OpenSSL make, Meson): вони не читають
        # CMAKE_C_FLAGS_INIT, тому потребують явної передачі шляхів.
        set(RPI_SYSROOT_MULTIARCH "${_ctslm_multiarch}" CACHE INTERNAL
            "Multiarch triple sysroot (відмінний від toolchain prefix)")
    endif()

    unset(_ctslm_lib)
    unset(_ctslm_usr)

    # -isystem: sysroot-хедери отримують пріоритет над host cross-include
    # (/usr/aarch64-linux-gnu/include з glibc 2.39 на Ubuntu 24.04).
    foreach(_ctslm_fvar CMAKE_C_FLAGS_INIT CMAKE_CXX_FLAGS_INIT)
        set(${_ctslm_fvar}
            "${${_ctslm_fvar}} -isystem${SYSROOT}/usr/include/${_ctslm_multiarch} -isystem${SYSROOT}/usr/include"
            CACHE INTERNAL "")
    endforeach()
    unset(_ctslm_fvar)

    # -L для libstdc++/libgcc_s із sysroot: запобігає лінкуванню з host
    # libstdc++ що вимагає новіший GLIBC ніж є у sysroot.
    # -L, а не -B: -B перенаправляє GCC-інструменти (cc1plus, collect2) на
    # директорію sysroot де вони є ARM64-бінарниками → "Exec format error".
    file(GLOB _ctslm_gcc_dirs
        "${SYSROOT}/usr/lib/gcc/${_ctslm_multiarch}/[0-9]*")
    if(_ctslm_gcc_dirs)
        list(SORT _ctslm_gcc_dirs ORDER DESCENDING)
        list(GET _ctslm_gcc_dirs 0 _ctslm_gcc_dir)
        foreach(_ctslm_fvar
                CMAKE_EXE_LINKER_FLAGS_INIT
                CMAKE_SHARED_LINKER_FLAGS_INIT
                CMAKE_MODULE_LINKER_FLAGS_INIT)
            set(${_ctslm_fvar}
                "${${_ctslm_fvar}} -L${_ctslm_gcc_dir}"
                CACHE INTERNAL "")
        endforeach()
        unset(_ctslm_fvar)
        unset(_ctslm_gcc_dir)
    endif()
    unset(_ctslm_gcc_dirs)
    unset(_ctslm_multiarch)
endmacro()

# ---------------------------------------------------------------------------
# cross_toolchain_apply_sysroot
#
# Валідує SYSROOT_VAR, встановлює CMAKE_SYSROOT та CMAKE_FIND_ROOT_PATH,
# після чого викликає cross_toolchain_setup_sysroot() або (якщо sysroot
# не задано) cross_toolchain_no_sysroot().
#
# Аргументи:
#   SYSROOT_VAR — ім'я змінної зі шляхом до sysroot (напр. RPI_SYSROOT)
#
# Використання:
#   cross_toolchain_apply_sysroot(RPI_SYSROOT)
# ---------------------------------------------------------------------------
macro(cross_toolchain_apply_sysroot SYSROOT_VAR)
    if(${SYSROOT_VAR})
        if(NOT IS_DIRECTORY "${${SYSROOT_VAR}}")
            message(FATAL_ERROR
                "[Toolchain] ${SYSROOT_VAR}='${${SYSROOT_VAR}}' не існує або не є директорією")
        endif()
        set(CMAKE_SYSROOT "${${SYSROOT_VAR}}")
        if(NOT "${${SYSROOT_VAR}}" IN_LIST CMAKE_FIND_ROOT_PATH)
            list(APPEND CMAKE_FIND_ROOT_PATH "${${SYSROOT_VAR}}")
        endif()
        cross_toolchain_setup_sysroot()
    else()
        cross_toolchain_no_sysroot()
    endif()
endmacro()
