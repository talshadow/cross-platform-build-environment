# cmake/external/GeographicLib.cmake
#
# Бібліотека геодезичних та картографічних обчислень:
# перетворення координат, геодезичні лінії, магнітне поле, геоїд тощо.
# https://geographiclib.sourceforge.io/
#
# Provides imported target:
#   GeographicLib::GeographicLib  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_GEOGRAPHICLIB  — ON: find_package в системі/sysroot
#                               OFF (за замовч.): зібрати через ExternalProject
#
# Кеш-змінні:
#   GEOGRAPHICLIB_VERSION    — версія (git тег)
#   GEOGRAPHICLIB_GIT_REPO   — URL git репозиторію

option(USE_SYSTEM_GEOGRAPHICLIB
    "Використовувати системну GeographicLib замість збірки з джерел"
    OFF)

set(GEOGRAPHICLIB_VERSION "2.4"
    CACHE STRING "Версія GeographicLib для збірки з джерел")

set(GEOGRAPHICLIB_GIT_REPO
    "https://github.com/geographiclib/geographiclib.git"
    CACHE STRING "Git репозиторій GeographicLib")

# ---------------------------------------------------------------------------

set(_geolib_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libGeographicLib.so")
set(_geolib_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_GEOGRAPHICLIB)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(GeographicLib REQUIRED)
    message(STATUS "[GeographicLib] Системна бібліотека: ${GeographicLib_LIBRARIES}")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    # GeographicLib встановлює CMake config-файл → find_package(GeographicLib)
    # знайде його і створить GeographicLib::GeographicLib автоматично.
    find_package(GeographicLib QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(GeographicLib_FOUND)
        message(STATUS "[GeographicLib] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")
        # GeographicLib::GeographicLib вже створено find_package

    elseif(EXISTS "${_geolib_lib}")
        ep_imported_library(GeographicLib::GeographicLib "${_geolib_lib}" "${_geolib_inc}")
        message(STATUS "[GeographicLib] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[GeographicLib] Буде зібрано з джерел (${GEOGRAPHICLIB_VERSION})")

        # Debian/RPi OS sysroot не має libm.so symlink (є тільки libm.so.6 + libm.a).
        # GCC при -lm вибирає libm.a (немає libm.so) → статичні long double функції
        # тягнуть __frexpl/__ldexpl тощо як undefined (glibc-internal, відсутні у .so).
        # Symlink libm.so → libm.so.6 у нашому prefix знаходиться першим через
        # -L${EXTERNAL_INSTALL_PREFIX}/lib, змушуючи лінкер взяти динамічну бібліотеку.
        if(CMAKE_CROSSCOMPILING AND CMAKE_SYSROOT
                AND NOT EXISTS "${EXTERNAL_INSTALL_PREFIX}/lib/libm.so")
            file(MAKE_DIRECTORY "${EXTERNAL_INSTALL_PREFIX}/lib")
            file(GLOB _libm_so6_paths
                "${CMAKE_SYSROOT}/lib/*/libm.so.6"
                "${CMAKE_SYSROOT}/usr/lib/*/libm.so.6"
                "${CMAKE_SYSROOT}/lib/libm.so.6")
            if(_libm_so6_paths)
                list(GET _libm_so6_paths 0 _libm_so6)
                file(CREATE_LINK "${_libm_so6}" "${EXTERNAL_INSTALL_PREFIX}/lib/libm.so" SYMBOLIC)
                message(STATUS "[GeographicLib] libm.so → ${_libm_so6}")
            endif()
            unset(_libm_so6_paths)
            unset(_libm_so6)
        endif()

        ep_cmake_args(_geolib_cmake_args
            # GeographicLib не має обов'язкових зовнішніх залежностей.
            # BUILD_SHARED_LIBS=ON вже передається ep_cmake_args.
            -DBUILD_DOCUMENTATION=OFF
            -DBUILD_EXAMPLES=OFF
            -DBUILD_MANPAGES=OFF
            # GCC 12 хибне спрацювання у TransverseMercator.cpp при -O2;
            # GeographicLib 2.x додає -Werror → збірка падає.
            # CMAKE_CXX_FLAGS_<Config> йде після COMPILE_OPTIONS у compile команді,
            # тому -Wno-maybe-uninitialized перекриває -Wall з GeographicLib CMakeLists.
            "-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=${CMAKE_CXX_FLAGS_RELWITHDEBINFO} -Wno-maybe-uninitialized"
            "-DCMAKE_CXX_FLAGS_RELEASE=${CMAKE_CXX_FLAGS_RELEASE} -Wno-maybe-uninitialized"
        )

        # GeographicLib не залежить від жодної з наших external бібліотек
        ExternalProject_Add(geographiclib_ep
            GIT_REPOSITORY  "${GEOGRAPHICLIB_GIT_REPO}"
            GIT_TAG         "v${GEOGRAPHICLIB_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/geographiclib"
            CMAKE_ARGS      ${_geolib_cmake_args}
            BUILD_BYPRODUCTS "${_geolib_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(
            GeographicLib::GeographicLib geographiclib_ep "${_geolib_lib}" "${_geolib_inc}")
    endif()
endif()

unset(_geolib_lib)
unset(_geolib_inc)
