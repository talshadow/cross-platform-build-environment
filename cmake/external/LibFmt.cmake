# cmake/external/LibFmt.cmake
#
# {fmt} — сучасна бібліотека форматування рядків для C++ (std::format-сумісна).
# https://github.com/fmtlib/fmt
#
# Provides imported target:
#   fmt::fmt  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_LIBFMT  — ON: find_package в системі/sysroot
#                        OFF (за замовченням): зібрати через ExternalProject
#
# Кеш-змінні:
#   LIBFMT_VERSION    — версія (git тег)
#   LIBFMT_GIT_REPO   — URL git репозиторію

option(USE_SYSTEM_LIBFMT
    "Використовувати системний libfmt (find_package) замість збірки з джерел"
    OFF)

set(LIBFMT_VERSION  "12.1.0"
    CACHE STRING "Версія {fmt} для збірки з джерел")

set(LIBFMT_GIT_REPO
    "https://github.com/fmtlib/fmt.git"
    CACHE STRING "Git репозиторій {fmt}")

# ---------------------------------------------------------------------------

set(_fmt_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libfmt.so")
set(_fmt_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_LIBFMT)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(fmt REQUIRED)
    message(STATUS "[LibFmt] Системна бібліотека версії ${fmt_VERSION}")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(fmt QUIET HINTS "${EXTERNAL_INSTALL_PREFIX}" NO_DEFAULT_PATH)
    if(fmt_FOUND)
        message(STATUS "[LibFmt] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[LibFmt] Буде зібрано з джерел (версія ${LIBFMT_VERSION})")

        ep_cmake_args(_fmt_cmake_args
            -DFMT_DOC=OFF
            -DFMT_TEST=OFF
            -DFMT_INSTALL=ON
        )

        ExternalProject_Add(libfmt_ep
            GIT_REPOSITORY  "${LIBFMT_GIT_REPO}"
            GIT_TAG         "${LIBFMT_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libfmt"
            CMAKE_ARGS      ${_fmt_cmake_args}
            BUILD_BYPRODUCTS "${_fmt_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(fmt::fmt libfmt_ep "${_fmt_lib}" "${_fmt_inc}")
    endif()
endif()

unset(_fmt_lib)
unset(_fmt_inc)
