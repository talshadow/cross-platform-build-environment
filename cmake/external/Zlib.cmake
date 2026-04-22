# cmake/external/Zlib.cmake
#
# Збирає або знаходить zlib.
# https://github.com/madler/zlib
#
# Provides imported target:
#   ZLIB::ZLIB  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_ZLIB  — ON: find_package в системі/sysroot
#                      OFF (за замовченням): зібрати через ExternalProject
#   ZLIB_USE_GIT     — ON: git clone / OFF (за замовченням): архів з GitHub Releases
#
# Кеш-змінні:
#   ZLIB_VERSION    — версія (без префіксу v)
#   ZLIB_GIT_REPO   — URL git репозиторію (тільки при ZLIB_USE_GIT=ON)

option(USE_SYSTEM_ZLIB
    "Використовувати системний zlib (find_package) замість збірки з джерел"
    ON)

option(ZLIB_USE_GIT
    "Завантажувати zlib через git clone (OFF = архів з GitHub Releases)"
    OFF)

set(ZLIB_VERSION  "1.3.1"
    CACHE STRING "Версія zlib для збірки з джерел")

set(ZLIB_GIT_REPO
    "https://github.com/madler/zlib.git"
    CACHE STRING "Git репозиторій zlib (використовується тільки при ZLIB_USE_GIT=ON)")

# ---------------------------------------------------------------------------

set(_zlib_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libz.so")
set(_zlib_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_ZLIB)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(ZLIB REQUIRED)
    message(STATUS "[Zlib] Системна бібліотека версії ${ZLIB_VERSION_STRING}")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(ZLIB QUIET HINTS "${EXTERNAL_INSTALL_PREFIX}" NO_DEFAULT_PATH)
    if(ZLIB_FOUND)
        message(STATUS "[Zlib] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_zlib_lib}")
        ep_imported_library(ZLIB::ZLIB "${_zlib_lib}" "${_zlib_inc}")
        message(STATUS "[Zlib] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[Zlib] Буде зібрано з джерел (версія ${ZLIB_VERSION})")

        if(ZLIB_USE_GIT)
            message(STATUS "[Zlib] Джерело: git clone (${ZLIB_GIT_REPO})")
            set(_zlib_download_args
                GIT_REPOSITORY  "${ZLIB_GIT_REPO}"
                GIT_TAG         "v${ZLIB_VERSION}"
                GIT_SHALLOW     ON
            )
        else()
            set(_zlib_archive_url
                "https://github.com/madler/zlib/archive/refs/tags/v${ZLIB_VERSION}.tar.gz")
            message(STATUS "[Zlib] Джерело: архів (${_zlib_archive_url})")
            set(_zlib_download_args
                URL                 "${_zlib_archive_url}"
                DOWNLOAD_EXTRACT_TIMESTAMP ON
            )
            unset(_zlib_archive_url)
        endif()

        ep_cmake_args(_zlib_cmake_args)

        ExternalProject_Add(zlib_ep
            ${_zlib_download_args}
            SOURCE_DIR      "${EP_SOURCES_DIR}/zlib"
            CMAKE_ARGS      ${_zlib_cmake_args}
            BUILD_BYPRODUCTS "${_zlib_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(ZLIB::ZLIB zlib_ep "${_zlib_lib}" "${_zlib_inc}")
        ep_track_cmake_file(zlib_ep "${CMAKE_CURRENT_LIST_FILE}")

        if(ZLIB_USE_GIT)
            ep_prestamp_git(zlib_ep "${EP_SOURCES_DIR}/zlib" "v${ZLIB_VERSION}")
        endif()
    endif()
endif()

unset(_zlib_lib)
unset(_zlib_inc)
