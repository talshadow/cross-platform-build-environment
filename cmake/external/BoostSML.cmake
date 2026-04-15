# cmake/external/BoostSML.cmake
#
# Boost.SML (boost-ext/sml) — header-only бібліотека State Machine Language.
# НЕ є частиною офіційного Boost — це розширення boost-ext.
# https://github.com/boost-ext/sml
#
# Provides imported target:
#   boost::sml  — INTERFACE IMPORTED (header-only)
#
# Опції:
#   USE_SYSTEM_BOOSTSML  — ON: find_package / OFF (default): ExternalProject
#
# Кеш-змінні:
#   BOOSTSML_VERSION, BOOSTSML_GIT_REPO

option(USE_SYSTEM_BOOSTSML
    "Використовувати системну Boost.SML замість збірки з джерел"
    OFF)

set(BOOSTSML_VERSION "v1.1.11"
    CACHE STRING "Версія Boost.SML (boost-ext/sml) для збірки з джерел")

set(BOOSTSML_GIT_REPO
    "https://github.com/boost-ext/sml.git"
    CACHE STRING "Git репозиторій Boost.SML")

# ---------------------------------------------------------------------------

set(_boostsml_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_BOOSTSML)
    # ── Системна бібліотека ─────────────────────────────────────────────────
    find_package(sml REQUIRED
        HINTS "${CMAKE_SYSROOT}/usr" "${CMAKE_SYSROOT}/usr/local")
    message(STATUS "[BoostSML] Системна: boost::sml")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(sml QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(sml_FOUND)
        message(STATUS "[BoostSML] Знайдено готові заголовки у ${EXTERNAL_INSTALL_PREFIX}")
        # boost::sml вже створено find_package

    elseif(EXISTS "${_boostsml_inc}/boost/sml.hpp")
        ep_imported_interface(boost::sml "${_boostsml_inc}")
        message(STATUS "[BoostSML] Знайдено заголовки у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[BoostSML] Буде встановлено з джерел (${BOOSTSML_VERSION})")

        ep_cmake_args(_boostsml_cmake_args
            -DSML_BUILD_TESTS=OFF
            -DSML_BUILD_EXAMPLES=OFF
        )

        ExternalProject_Add(boostsml_ep
            GIT_REPOSITORY  "${BOOSTSML_GIT_REPO}"
            GIT_TAG         "${BOOSTSML_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/boostsml"
            CMAKE_ARGS      ${_boostsml_cmake_args}
            BUILD_BYPRODUCTS "${_boostsml_inc}/boost/sml.hpp"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_interface_from_ep(boost::sml boostsml_ep "${_boostsml_inc}")
    endif()
endif()

unset(_boostsml_inc)
