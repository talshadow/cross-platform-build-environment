# cmake/external/LibIr.cmake
#
# libir — бібліотека для роботи з інфрачервоним (IR) обладнанням.
# TODO: уточнити репозиторій та URL для завантаження.
#
# Provides imported target:
#   libir::libir  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_LIBIR  — ON: find_package / OFF (default): ExternalProject
#
# Кеш-змінні:
#   LIBIR_VERSION, LIBIR_GIT_REPO

option(USE_SYSTEM_LIBIR
    "Використовувати системну libir замість збірки з джерел"
    OFF)

set(LIBIR_VERSION "1.0.0"
    CACHE STRING "Версія libir для збірки з джерел")

# TODO: замінити на реальний URL репозиторію
set(LIBIR_GIT_REPO
    ""
    CACHE STRING "Git репозиторій libir")

# ---------------------------------------------------------------------------

set(_libir_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libir.so")
set(_libir_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_LIBIR)
    # ── Системна бібліотека ─────────────────────────────────────────────────
    find_package(libir REQUIRED)
    if(NOT TARGET libir::libir)
        # Fallback: pkg-config
        find_package(PkgConfig QUIET)
        if(PkgConfig_FOUND)
            pkg_check_modules(LIBIR REQUIRED IMPORTED_TARGET libir)
            if(NOT TARGET libir::libir)
                add_library(libir::libir INTERFACE IMPORTED GLOBAL)
                set_property(TARGET libir::libir
                    APPEND PROPERTY INTERFACE_LINK_LIBRARIES PkgConfig::LIBIR)
            endif()
        endif()
    endif()
    message(STATUS "[LibIr] Системна: libir::libir")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(libir QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(libir_FOUND)
        message(STATUS "[LibIr] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_libir_lib}")
        ep_imported_library(libir::libir "${_libir_lib}" "${_libir_inc}")
        message(STATUS "[LibIr] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(LIBIR_GIT_REPO STREQUAL "")
        message(WARNING "[LibIr] LIBIR_GIT_REPO не задано — встановіть -DLIBIR_GIT_REPO=<url> або -DUSE_SYSTEM_LIBIR=ON")

    else()
        message(STATUS "[LibIr] Буде зібрано з джерел (${LIBIR_VERSION})")

        ep_cmake_args(_libir_cmake_args)

        ExternalProject_Add(libir_ep
            GIT_REPOSITORY  "${LIBIR_GIT_REPO}"
            GIT_TAG         "${LIBIR_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libir"
            CMAKE_ARGS      ${_libir_cmake_args}
            BUILD_BYPRODUCTS "${_libir_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(libir::libir libir_ep "${_libir_lib}" "${_libir_inc}")
    endif()
endif()

unset(_libir_lib)
unset(_libir_inc)
