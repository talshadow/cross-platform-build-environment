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
cross_toolchain_find_versioned_cross_compiler(
    "${RPI4_TOOLCHAIN_PREFIX}"
    "${RPI4_GCC_VERSION}")

if(NOT _vcc_found)
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
unset(_vcc_found)

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
# -std=gnu11: GNU extensions потрібні для Linux kernel headers
# (linux/videodev2.h та інші використовують struct timespec без включення <time.h>).
# -std=c++20: стандарт C++20 для C++. Для крос-збірок fix стосовно strtoul
# для C++ забезпечується через preamble у Meson cross-file (Common.cmake).
set(CMAKE_C_FLAGS_INIT   "${_BASE_FLAGS} -std=gnu11"   CACHE INTERNAL "")
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

cross_toolchain_apply_sysroot(RPI_SYSROOT)

if(RPI_SYSROOT)
    cross_toolchain_setup_linux_multiarch(
        "${RPI4_TOOLCHAIN_PREFIX}"
        "${RPI_SYSROOT}"
        "RaspberryPi4"
        "aarch64-linux-gnu" "aarch64-linux-gnueabi")
endif()
