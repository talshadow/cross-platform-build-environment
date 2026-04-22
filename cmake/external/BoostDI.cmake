# cmake/external/BoostDI.cmake
#
# Boost.DI (boost-ext/di) — header-only бібліотека dependency injection.
# НЕ є частиною офіційного Boost — це розширення boost-ext.
# https://github.com/boost-ext/di
#
# Provides imported target:
#   boost::di  — INTERFACE IMPORTED (header-only)
#
# Опції:
#   USE_SYSTEM_BOOSTDI  — ON: find_package / OFF (default): ExternalProject
#
# Кеш-змінні:
#   BOOSTDI_VERSION, BOOSTDI_GIT_REPO

option(USE_SYSTEM_BOOSTDI
    "Використовувати системну Boost.DI замість збірки з джерел"
    OFF)

set(BOOSTDI_VERSION "v1.3.0"
    CACHE STRING "Версія Boost.DI (boost-ext/di) для збірки з джерел")

set(BOOSTDI_GIT_REPO
    "https://github.com/boost-ext/di.git"
    CACHE STRING "Git репозиторій Boost.DI")

# ---------------------------------------------------------------------------

set(_boostdi_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_BOOSTDI)
    # ── Системна бібліотека ─────────────────────────────────────────────────
    find_package(di REQUIRED
        HINTS "${CMAKE_SYSROOT}/usr" "${CMAKE_SYSROOT}/usr/local")
    message(STATUS "[BoostDI] Системна: boost::di")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(di QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(di_FOUND)
        message(STATUS "[BoostDI] Знайдено готові заголовки у ${EXTERNAL_INSTALL_PREFIX}")
        # boost::di вже створено find_package

    elseif(EXISTS "${_boostdi_inc}/boost/di.hpp")
        ep_imported_interface(boost::di "${_boostdi_inc}")
        message(STATUS "[BoostDI] Знайдено заголовки у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[BoostDI] Буде встановлено з джерел (${BOOSTDI_VERSION})")

        ep_cmake_args(_boostdi_cmake_args
            -DBOOST_DI_OPT_BUILD_TESTS=OFF
            -DBOOST_DI_OPT_BUILD_EXAMPLES=OFF
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        )

        ExternalProject_Add(boostdi_ep
            GIT_REPOSITORY  "${BOOSTDI_GIT_REPO}"
            GIT_TAG         "${BOOSTDI_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/boostdi"
            CMAKE_ARGS      ${_boostdi_cmake_args}
            BUILD_COMMAND   ""
            INSTALL_COMMAND
                ${CMAKE_COMMAND} -E copy_directory
                    "${EP_SOURCES_DIR}/boostdi/include"
                    "${EXTERNAL_INSTALL_PREFIX}/include"
                COMMAND ${CMAKE_COMMAND} -E copy_directory
                    "${EP_SOURCES_DIR}/boostdi/extension/include"
                    "${EXTERNAL_INSTALL_PREFIX}/include"
            BUILD_BYPRODUCTS "${_boostdi_inc}/boost/di.hpp"
            LOG_DOWNLOAD    ON
            LOG_INSTALL     ON
        )

        ep_imported_interface_from_ep(boost::di boostdi_ep "${_boostdi_inc}")
        ep_track_cmake_file(boostdi_ep "${CMAKE_CURRENT_LIST_FILE}")
    endif()
endif()

unset(_boostdi_inc)
