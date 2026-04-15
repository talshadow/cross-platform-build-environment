# cmake/external/LibPng.cmake
#
# Збирає або знаходить libpng.
#
# Provides imported target:
#   PNG::PNG  — SHARED IMPORTED (або INTERFACE при USE_SYSTEM_LIBPNG=ON)
#
# Опції:
#   USE_SYSTEM_LIBPNG  — ON: find_package в системі/sysroot
#                        OFF (за замовченням): зібрати через ExternalProject
#
# Кеш-змінні:
#   LIBPNG_VERSION    — версія (git тег)
#   LIBPNG_GIT_REPO   — URL git репозиторію

option(USE_SYSTEM_LIBPNG
    "Використовувати системний libpng (find_package) замість збірки з джерел"
    OFF)

set(LIBPNG_VERSION  "1.6.43"
    CACHE STRING "Версія libpng для збірки з джерел")

set(LIBPNG_GIT_REPO
    "https://github.com/pnggroup/libpng.git"
    CACHE STRING "Git репозиторій libpng")

# ---------------------------------------------------------------------------

set(_png_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libpng.so")
set(_png_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_LIBPNG)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    # При крос-компіляції toolchain вже налаштовує CMAKE_FIND_ROOT_PATH на
    # sysroot, тому find_package автоматично шукає в правильному місці.
    find_package(PNG REQUIRED)
    message(STATUS "[LibPng] Системна бібліотека: ${PNG_LIBRARIES}")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    # HINTS + NO_DEFAULT_PATH: шукати лише в EXTERNAL_INSTALL_PREFIX, не в системі.
    find_package(PNG QUIET HINTS "${EXTERNAL_INSTALL_PREFIX}" NO_DEFAULT_PATH)
    if(PNG_FOUND)
        message(STATUS "[LibPng] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[LibPng] Буде зібрано з джерел (версія ${LIBPNG_VERSION})")

        ep_cmake_args(_png_cmake_args
            -DPNG_SHARED=ON
            -DPNG_STATIC=OFF
            -DPNG_TESTS=OFF
            -DPNG_TOOLS=OFF
        )

        ExternalProject_Add(libpng_ep
            GIT_REPOSITORY  "${LIBPNG_GIT_REPO}"
            GIT_TAG         "v${LIBPNG_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libpng"
            CMAKE_ARGS      ${_png_cmake_args}
            BUILD_BYPRODUCTS "${_png_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(PNG::PNG libpng_ep "${_png_lib}" "${_png_inc}")
    endif()
endif()

unset(_png_lib)
unset(_png_inc)
