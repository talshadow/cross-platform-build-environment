# cmake/external/LibPisp.cmake
#
# libpisp — Raspberry Pi ISP (Image Signal Processor) бібліотека.
# Відповідає за конфігурацію та керування апаратним ISP RPi 5.
# Пакети debian: libpisp-common (заголовки/дані) + libpisp1 (shared lib).
# https://github.com/raspberrypi/libpisp
#
# Provides imported target:
#   libpisp::libpisp  — SHARED IMPORTED
#
# Залежності:
#   - libcamera::libcamera (libcamera_ep)
#   - Boost::headers       (boost_ep) — Boost.log, Boost.program_options
#
# Примітки:
#   - USE_SYSTEM_LIBPISP=ON (за замовч.) — знайти в sysroot/системі.
#     libpisp присутня в Raspberry Pi OS Bookworm (RPi5).
#   - USE_SYSTEM_LIBPISP=OFF — зібрати з джерел через Meson.
#
# Опції:
#   USE_SYSTEM_LIBPISP  — ON (за замовч.): find_package / pkg-config
#                         OFF: зібрати через Meson ExternalProject
#
# Кеш-змінні:
#   LIBPISP_VERSION, LIBPISP_GIT_REPO

option(USE_SYSTEM_LIBPISP
    "Використовувати системну libpisp замість збірки з джерел (рекомендовано)"
    OFF)

set(LIBPISP_VERSION "v1.0.7"
    CACHE STRING "Версія libpisp для збірки з джерел")

set(LIBPISP_GIT_REPO
    "https://github.com/raspberrypi/libpisp.git"
    CACHE STRING "Git репозиторій libpisp")

# ---------------------------------------------------------------------------

set(_libpisp_lib  "${EXTERNAL_INSTALL_PREFIX}/lib/libpisp.so")
set(_libpisp_inc  "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_LIBPISP)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(libpisp QUIET)
    if(libpisp_FOUND)
        message(STATUS "[LibPisp] Системна: libpisp::libpisp")
    else()
        find_package(PkgConfig QUIET)
        if(PkgConfig_FOUND)
            pkg_check_modules(LIBPISP IMPORTED_TARGET libpisp)
            if(LIBPISP_FOUND)
                if(NOT TARGET libpisp::libpisp)
                    add_library(libpisp::libpisp INTERFACE IMPORTED GLOBAL)
                    set_property(TARGET libpisp::libpisp
                        APPEND PROPERTY INTERFACE_LINK_LIBRARIES PkgConfig::LIBPISP)
                endif()
                message(STATUS "[LibPisp] Системна (pkg-config): ${LIBPISP_LIBRARIES}")
            else()
                message(WARNING "[LibPisp] USE_SYSTEM_LIBPISP=ON але libpisp не знайдено. "
                    "Встановіть libpisp-dev (доступна на RPi5/Bookworm) або передайте "
                    "USE_SYSTEM_LIBPISP=OFF для збірки з джерел.")
            endif()
        else()
            message(WARNING "[LibPisp] USE_SYSTEM_LIBPISP=ON але libpisp не знайдено "
                "(pkg-config недоступний). Встановіть libpisp-dev.")
        endif()
    endif()

else()
    # ── Алгоритм: find_package → ExternalProject_Add (Meson) ───────────────
    find_package(libpisp QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(libpisp_FOUND)
        message(STATUS "[LibPisp] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_libpisp_lib}")
        ep_imported_library(libpisp::libpisp "${_libpisp_lib}" "${_libpisp_inc}")
        message(STATUS "[LibPisp] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[LibPisp] Буде зібрано з джерел (${LIBPISP_VERSION}) через Meson")

        _ep_require_meson()
        find_program(_libpisp_meson meson)
        find_program(_libpisp_ninja ninja)
        _ep_cmake_to_meson_buildtype(_libpisp_meson_bt)

        # Генеруємо meson cross-file
        _meson_generate_cross_file(_libpisp_cross_args)

        # Boost include dir для передачі в Meson
        set(_libpisp_boost_inc "")
        if(TARGET Boost::headers)
            get_target_property(_libpisp_boost_inc Boost::headers INTERFACE_INCLUDE_DIRECTORIES)
        endif()
        if(NOT _libpisp_boost_inc)
            set(_libpisp_boost_inc "${EXTERNAL_INSTALL_PREFIX}/include")
        endif()

        ExternalProject_Add(libpisp_ep
            GIT_REPOSITORY  "${LIBPISP_GIT_REPO}"
            GIT_TAG         "${LIBPISP_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libpisp"
            CONFIGURE_COMMAND
                env
                    PKG_CONFIG_PATH=${EXTERNAL_INSTALL_PREFIX}/lib/pkgconfig:${EXTERNAL_INSTALL_PREFIX}/share/pkgconfig
                    BOOST_ROOT=${EXTERNAL_INSTALL_PREFIX}
                ${_libpisp_meson} setup
                    --reconfigure
                    ${_libpisp_cross_args}
                    --prefix=${EXTERNAL_INSTALL_PREFIX}
                    --libdir=lib
                    --buildtype=${_libpisp_meson_bt}
                    -Dcpp_args=-Wno-unused-parameter
                    <BINARY_DIR>
                    <SOURCE_DIR>
            BUILD_COMMAND
                ${_libpisp_ninja} -C "<BINARY_DIR>" -j${_EP_NPROC}
            INSTALL_COMMAND
                ${_libpisp_ninja} -C "<BINARY_DIR>" install
            BUILD_BYPRODUCTS "${_libpisp_lib}"
            LOG_DOWNLOAD    ON
            LOG_CONFIGURE   ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(
            libpisp::libpisp libpisp_ep "${_libpisp_lib}" "${_libpisp_inc}")

        ep_track_cmake_file(libpisp_ep "${CMAKE_CURRENT_LIST_FILE}")

        ep_prestamp_git(libpisp_ep "${EP_SOURCES_DIR}/libpisp" "${LIBPISP_VERSION}")

        unset(_libpisp_meson)
        unset(_libpisp_ninja)
        unset(_libpisp_cross_args)
        unset(_libpisp_ep_deps)
        unset(_libpisp_boost_inc)
    endif()
endif()

unset(_libpisp_lib)
unset(_libpisp_inc)
