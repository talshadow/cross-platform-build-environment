# cmake/toolchains/RaspberryPi4.cmake
#
# Toolchain для Raspberry Pi 4 Model B / 400 / CM4
# SoC:  BCM2711
# CPU:  Cortex-A72 × 4 (ARMv8-A, 64-bit)
# OS:   Raspberry Pi OS 64-bit / Ubuntu Server 22.04/24.04 arm64
#
# Пакети Ubuntu: gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
#
# Використання:
#   cmake -B build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/RaspberryPi4.cmake \
#     [-DRPI_SYSROOT=/path/to/sysroot]

cmake_minimum_required(VERSION 3.28)

set(CMAKE_SYSTEM_NAME      Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(RPI4_TOOLCHAIN_PREFIX "aarch64-linux-gnu"
    CACHE STRING "Префікс крос-компілятора для Raspberry Pi 4")

set(RPI4_GCC_VERSION "12"
    CACHE STRING "Версія GCC для крос-компіляції RPi 4 (12, 13, ...)")

set(_TOOLCHAIN_PREFIX_VAR RPI4_TOOLCHAIN_PREFIX)
include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

# Шукаємо версований компілятор (aarch64-linux-gnu-gcc-12),
# якщо не знайдено — fallback на неверсований (aarch64-linux-gnu-gcc)
find_program(_RPI4_CC_VERSIONED
    "${RPI4_TOOLCHAIN_PREFIX}-gcc-${RPI4_GCC_VERSION}"
    HINTS ENV PATH)

if(_RPI4_CC_VERSIONED)
    find_program(_RPI4_CXX_VERSIONED
        "${RPI4_TOOLCHAIN_PREFIX}-g++-${RPI4_GCC_VERSION}"
        HINTS ENV PATH)
    set(CMAKE_C_COMPILER   "${_RPI4_CC_VERSIONED}"  CACHE FILEPATH "C compiler"   FORCE)
    set(CMAKE_CXX_COMPILER "${_RPI4_CXX_VERSIONED}" CACHE FILEPATH "C++ compiler" FORCE)
    unset(_RPI4_CXX_VERSIONED)
    find_program(_AR    "${RPI4_TOOLCHAIN_PREFIX}-ar")
    find_program(_STRIP "${RPI4_TOOLCHAIN_PREFIX}-strip")
    find_program(_RANLIB "${RPI4_TOOLCHAIN_PREFIX}-ranlib")
    if(_AR)
        set(CMAKE_AR     "${_AR}"     CACHE FILEPATH "Archiver" FORCE)
    endif()
    if(_STRIP)
        set(CMAKE_STRIP  "${_STRIP}"  CACHE FILEPATH "Strip"    FORCE)
    endif()
    if(_RANLIB)
        set(CMAKE_RANLIB "${_RANLIB}" CACHE FILEPATH "Ranlib"   FORCE)
    endif()
    unset(_AR)
    unset(_STRIP)
    unset(_RANLIB)
else()
    # Перевіряємо чи неверсований компілятор є CT-NG toolchain.
    # CT-NG завжди виводить "crosstool-NG" у рядку --version,
    # тому попередження про відсутність версованого gcc не актуальне:
    # CT-NG за замовчуванням не створює версованих симлінків.
    find_program(_RPI4_CC_PLAIN "${RPI4_TOOLCHAIN_PREFIX}-gcc" HINTS ENV PATH)
    set(_rpi4_is_ctng FALSE)
    if(_RPI4_CC_PLAIN)
        execute_process(
            COMMAND "${_RPI4_CC_PLAIN}" --version
            OUTPUT_VARIABLE _rpi4_ver_str
            ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(_rpi4_ver_str MATCHES "crosstool-NG")
            set(_rpi4_is_ctng TRUE)
        endif()
        unset(_rpi4_ver_str)
    endif()
    unset(_RPI4_CC_PLAIN)

    if(NOT _rpi4_is_ctng)
        message(WARNING
            "[RaspberryPi4] gcc-${RPI4_GCC_VERSION} не знайдено, "
            "використовується неверсований aarch64-linux-gnu-gcc.\n"
            "  Ubuntu/Debian : sudo apt install gcc-${RPI4_GCC_VERSION}-aarch64-linux-gnu\n"
            "  Arch/CachyOS  : aarch64-linux-gnu-gcc встановлюється без версії (пакет aarch64-linux-gnu-gcc)")
    endif()
    unset(_rpi4_is_ctng)

    set(_rpi4_install_hint
        "gcc-${RPI4_GCC_VERSION}-aarch64-linux-gnu g++-${RPI4_GCC_VERSION}-aarch64-linux-gnu")
    cross_toolchain_find_compiler("${RPI4_TOOLCHAIN_PREFIX}" "${_rpi4_install_hint}")
    unset(_rpi4_install_hint)
endif()
unset(_RPI4_CC_VERSIONED)

# --- Оптимізаційні прапори для Raspberry Pi 4 (Cortex-A72) ---

# Архітектура: BCM2711, Cortex-A72, ARMv8-A
# Примітка: -mfloat-abi не застосовується для AArch64 (float через FPU завжди)
set(_ARCH_FLAGS "-mcpu=cortex-a72 -march=armv8-a+crc+simd")

# Векторизація: NEON auto-vectorization з динамічним cost model
set(_VECT_FLAGS "-ftree-vectorize -fsimd-cost-model=dynamic")

# Математика: точність IEEE 754 (критично для OpenCV та геодезичних обчислень)
set(_MATH_FLAGS "-fno-unsafe-math-optimizations -fno-finite-math-only -fno-math-errno")

# Базові прапори — в усі конфігурації
set(_BASE_FLAGS "${_ARCH_FLAGS} ${_VECT_FLAGS} ${_MATH_FLAGS}")

# LTO: паралельна оптимізація по всіх ядрах (Release/RelWithDebInfo)
set(_LTO_FLAGS "-flto=auto -fno-fat-lto-objects")

# Оптимізації циклів та вирівнювання функцій (Release/RelWithDebInfo)
set(_LOOP_FLAGS "-falign-functions=16 -floop-nest-optimize -ftree-loop-distribution")

# --- CMAKE_*_INIT для CMake-based збірок ---
# Читаються CMake до кешу; автоматично передаються EP суб-збіркам через
# -DCMAKE_TOOLCHAIN_FILE.
# -std=c11: strict C11 запобігає auto -D_GNU_SOURCE → glibc не ремапить
# strtoul → __isoc23_strtoul@GLIBC_2.38 (відсутній у target glibc < 2.38).
# -std=c++20: стандарт C++20 для C++. Для крос-збірок fix стосовно strtoul
# для C++ забезпечується через preamble у Meson cross-file (Common.cmake).
set(CMAKE_C_FLAGS_INIT   "${_BASE_FLAGS} -std=c11"   CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "${_BASE_FLAGS} -std=c++20" CACHE INTERNAL "")

set(CMAKE_C_FLAGS_RELEASE_INIT           "-O2 -DNDEBUG -s ${_LOOP_FLAGS} ${_LTO_FLAGS}" CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_RELEASE_INIT         "-O2 -DNDEBUG -s ${_LOOP_FLAGS} ${_LTO_FLAGS}" CACHE INTERNAL "")
set(CMAKE_EXE_LINKER_FLAGS_RELEASE_INIT    "${_LTO_FLAGS}" CACHE INTERNAL "")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE_INIT "${_LTO_FLAGS}" CACHE INTERNAL "")
set(CMAKE_MODULE_LINKER_FLAGS_RELEASE_INIT "${_LTO_FLAGS}" CACHE INTERNAL "")

set(CMAKE_C_FLAGS_RELWITHDEBINFO_INIT         "-O2 -g -DNDEBUG ${_LOOP_FLAGS} ${_LTO_FLAGS}" CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO_INIT       "-O2 -g -DNDEBUG ${_LOOP_FLAGS} ${_LTO_FLAGS}" CACHE INTERNAL "")
set(CMAKE_EXE_LINKER_FLAGS_RELWITHDEBINFO_INIT    "${_LTO_FLAGS}" CACHE INTERNAL "")
set(CMAKE_SHARED_LINKER_FLAGS_RELWITHDEBINFO_INIT "${_LTO_FLAGS}" CACHE INTERNAL "")
set(CMAKE_MODULE_LINKER_FLAGS_RELWITHDEBINFO_INIT "${_LTO_FLAGS}" CACHE INTERNAL "")

set(CMAKE_C_FLAGS_DEBUG_INIT   "-O0 -g -DDEBUG" CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_DEBUG_INIT "-O0 -g -DDEBUG" CACHE INTERNAL "")

# --- Прапори для non-CMake збірок (OpenSSL make, Meson) ---
# EP_EXTRA_CFLAGS / EP_EXTRA_LDFLAGS: читаються з OpenSSL.cmake (env CFLAGS/LDFLAGS)
# та Common.cmake (_meson_generate_cross_file → c_args/cpp_args у cross-файлі).
# Містять: базові + per-type прапори відповідно до CMAKE_BUILD_TYPE.
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(_EP_TYPE_CFLAGS  "-O2 -DNDEBUG -s ${_LOOP_FLAGS} ${_LTO_FLAGS}")
    set(_EP_TYPE_LDFLAGS "${_LTO_FLAGS}")
elseif(CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    set(_EP_TYPE_CFLAGS  "-O2 -g -DNDEBUG ${_LOOP_FLAGS} ${_LTO_FLAGS}")
    set(_EP_TYPE_LDFLAGS "${_LTO_FLAGS}")
else()
    set(_EP_TYPE_CFLAGS  "-O0 -g -DDEBUG")
    set(_EP_TYPE_LDFLAGS "")
endif()
set(EP_EXTRA_CFLAGS  "${_BASE_FLAGS} ${_EP_TYPE_CFLAGS}"  CACHE INTERNAL
    "C/CXX прапори для non-cmake EP збірок (OpenSSL, Meson)")
set(EP_EXTRA_LDFLAGS "${_EP_TYPE_LDFLAGS}"                CACHE INTERNAL
    "Лінкер прапори для non-cmake EP збірок (LTO тощо)")

unset(_ARCH_FLAGS)
unset(_VECT_FLAGS)
unset(_MATH_FLAGS)
unset(_BASE_FLAGS)
unset(_LTO_FLAGS)
unset(_LOOP_FLAGS)
unset(_EP_TYPE_CFLAGS)
unset(_EP_TYPE_LDFLAGS)

# --- Sysroot ---------------------------------------------------------------
set(RPI_SYSROOT "" CACHE PATH
    "Шлях до sysroot Raspberry Pi (порожньо = збірка без sysroot)")

if(RPI_SYSROOT)
    if(NOT IS_DIRECTORY "${RPI_SYSROOT}")
        message(FATAL_ERROR
            "[Toolchain] RPI_SYSROOT не існує: '${RPI_SYSROOT}'")
    endif()
    set(CMAKE_SYSROOT "${RPI_SYSROOT}")
    if(NOT "${RPI_SYSROOT}" IN_LIST CMAKE_FIND_ROOT_PATH)
        list(APPEND CMAKE_FIND_ROOT_PATH "${RPI_SYSROOT}")
    endif()
    cross_toolchain_setup_sysroot()

    # Debian multiarch sysroot (RPi OS): бібліотеки лежать у
    # lib/aarch64-linux-gnu/, а не в lib/ як очікує Arch cross-compiler.
    # Додаємо ці шляхи явно щоб лінкер знаходив libc.so.6 тощо.
    #
    # ВАЖЛИВО: multiarch-триплет у sysroot може відрізнятися від префіксу
    # toolchain. Наприклад, CT-NG toolchain з префіксом aarch64-unknown-linux-gnu
    # може цілитися в Debian sysroot, де бібліотеки лежать у aarch64-linux-gnu/.
    # Автовизначаємо реальний триплет по наявності директорії у sysroot.
    if(IS_DIRECTORY "${RPI_SYSROOT}/lib/${RPI4_TOOLCHAIN_PREFIX}")
        set(_SYSROOT_MULTIARCH "${RPI4_TOOLCHAIN_PREFIX}")
    else()
        foreach(_triple "aarch64-linux-gnu" "aarch64-linux-gnueabi")
            if(IS_DIRECTORY "${RPI_SYSROOT}/lib/${_triple}")
                set(_SYSROOT_MULTIARCH "${_triple}")
                break()
            endif()
        endforeach()
        if(NOT _SYSROOT_MULTIARCH)
            set(_SYSROOT_MULTIARCH "${RPI4_TOOLCHAIN_PREFIX}")
            message(WARNING
                "[RaspberryPi4] Не вдалося визначити multiarch-триплет sysroot, "
                "використовується ${_SYSROOT_MULTIARCH}")
        else()
            message(STATUS
                "[RaspberryPi4] Sysroot multiarch: ${_SYSROOT_MULTIARCH} "
                "(toolchain prefix: ${RPI4_TOOLCHAIN_PREFIX})")
        endif()
    endif()

    set(_MULTIARCH_LIB "${RPI_SYSROOT}/lib/${_SYSROOT_MULTIARCH}")
    set(_MULTIARCH_USR "${RPI_SYSROOT}/usr/lib/${_SYSROOT_MULTIARCH}")

    # -L: лінкер знаходить libc.so.6 та інші розділені бібліотеки
    foreach(_flags_var CMAKE_EXE_LINKER_FLAGS_INIT
                       CMAKE_SHARED_LINKER_FLAGS_INIT
                       CMAKE_MODULE_LINKER_FLAGS_INIT)
        set(${_flags_var}
            "-L${_MULTIARCH_LIB} -L${_MULTIARCH_USR} ${${_flags_var}}"
            CACHE INTERNAL "")
    endforeach()

    # Наступні прапори потрібні лише коли триплет toolchain відрізняється від
    # multiarch-триплета sysroot (напр. CT-NG aarch64-unknown-linux-gnu →
    # Debian sysroot aarch64-linux-gnu).  Коли вони збігаються (стандартний
    # Ubuntu cross-compiler), GCC вже знає ці шляхи автоматично.
    if(NOT _SYSROOT_MULTIARCH STREQUAL RPI4_TOOLCHAIN_PREFIX)
        # -B: GCC-driver знаходить startup-файли (crt1.o, crti.o).
        # CT-NG з триплетом aarch64-unknown-linux-gnu не знає де шукати
        # crt1.o у Debian sysroot — вказуємо явно.
        set(_multiarch_extra " -B${_MULTIARCH_LIB} -B${_MULTIARCH_USR}")
        string(CONCAT _multiarch_extra ${_multiarch_extra})
        foreach(_flags_var CMAKE_C_FLAGS_INIT CMAKE_CXX_FLAGS_INIT)
            set(${_flags_var}
                "${${_flags_var}}${_multiarch_extra}"
                CACHE INTERNAL "")
        endforeach()
        unset(_multiarch_extra)

        # Виставляємо CACHE-змінну для не-cmake sub-builds (OpenSSL make, meson):
        # вони не читають CMAKE_C_FLAGS_INIT, тому потребують явної передачі шляхів.
        # Змінна встановлюється ТІЛЬКИ коли триплети різняться — Ubuntu build
        # (де вони збігаються) цю змінну не отримує, поведінка залишається незмінною.
        set(RPI_SYSROOT_MULTIARCH "${_SYSROOT_MULTIARCH}" CACHE INTERNAL
            "Multiarch triple sysroot (відмінний від toolchain prefix)")
    endif()

    # Ubuntu 24.04 встановлює libc6-dev-arm64-cross з glibc 2.39 хедерами до
    # /usr/aarch64-linux-gnu/include — цей шлях GCC шукає ПЕРЕД sysroot-хедерами
    # у своїх вбудованих include-шляхах.  Результат: код компілюється з glibc 2.39
    # символами (__isoc23_strtol, __ldexp тощо), яких немає у старому sysroot.
    # -isystem, вказані на командному рядку, шукаються ДО вбудованих system-шляхів,
    # тому sysroot-хедери отримують пріоритет над host cross-include.
    foreach(_flags_var CMAKE_C_FLAGS_INIT CMAKE_CXX_FLAGS_INIT)
        set(${_flags_var}
            "${${_flags_var}} -isystem${RPI_SYSROOT}/usr/include/${_SYSROOT_MULTIARCH} -isystem${RPI_SYSROOT}/usr/include"
            CACHE INTERNAL "")
    endforeach()

    unset(_MULTIARCH_LIB)
    unset(_MULTIARCH_USR)

    # Host cross-compiler libstdc++ може посилатись на символи GLIBC новіші
    # за ті що є у sysroot (напр. Ubuntu 24.04 gcc-12 потребує GLIBC_2.38,
    # але RPi OS sysroot має лише GLIBC_2.36; Arch GCC 15 + sysroot GCC 12 —
    # аналогічна ситуація).  Перенаправляємо linker на libstdc++/libgcc_s із
    # самого sysroot через -L.
    #
    # Чому -L, а не -B:
    #   -B перенаправляє всі GCC-інструменти (cc1plus, collect2 тощо) на
    #   директорію sysroot, де вони є ARM64-бінарниками — виконання падає з
    #   "Exec format error".  -L лише додає шлях до бібліотек у лінкері;
    #   GCC-інструменти не зачіпаються.  Пошук бібліотек у -L виконується
    #   раніше ніж GCC автоматично додає свою внутрішню директорію
    #   (/usr/lib/gcc-cross/…), тому sysroot libstdc++ отримує пріоритет.
    file(GLOB _SYSROOT_GCC_DIRS
        "${RPI_SYSROOT}/usr/lib/gcc/${_SYSROOT_MULTIARCH}/[0-9]*")
    if(_SYSROOT_GCC_DIRS)
        list(SORT _SYSROOT_GCC_DIRS ORDER DESCENDING)
        list(GET _SYSROOT_GCC_DIRS 0 _SYSROOT_GCC_DIR)

        foreach(_flags_var CMAKE_EXE_LINKER_FLAGS_INIT
                           CMAKE_SHARED_LINKER_FLAGS_INIT
                           CMAKE_MODULE_LINKER_FLAGS_INIT)
            set(${_flags_var}
                "${${_flags_var}} -L${_SYSROOT_GCC_DIR}"
                CACHE INTERNAL "")
        endforeach()

        unset(_SYSROOT_GCC_DIR)
    endif()
    unset(_SYSROOT_GCC_DIRS)
    unset(_SYSROOT_MULTIARCH)
else()
    if(CMAKE_CROSSCOMPILING)
        message(FATAL_ERROR
            "[RaspberryPi4] RPI_SYSROOT не задано. "
            "Для крос-компіляції задайте -DRPI_SYSROOT=<path>")
    endif()
    cross_toolchain_no_sysroot()
endif()
