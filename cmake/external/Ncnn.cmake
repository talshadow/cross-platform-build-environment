# cmake/external/Ncnn.cmake
#
# ncnn — високопродуктивна нейромережева бібліотека для інференсу на мобільних/embedded платформах.
# Оптимізована для ARM (NEON) — підходить для Raspberry Pi.
# https://github.com/Tencent/ncnn
#
# Provides imported target:
#   ncnn::ncnn  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_NCNN  — ON: find_package / OFF (default): ExternalProject
#
# Кеш-змінні:
#   NCNN_VERSION, NCNN_GIT_REPO

option(USE_SYSTEM_NCNN
    "Використовувати системну ncnn замість збірки з джерел"
    OFF)

set(NCNN_VERSION "20240410"
    CACHE STRING "Версія ncnn для збірки з джерел")

set(NCNN_GIT_REPO
    "https://github.com/Tencent/ncnn.git"
    CACHE STRING "Git репозиторій ncnn")

# ---------------------------------------------------------------------------

set(_ncnn_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libncnn.so")
set(_ncnn_inc "${EXTERNAL_INSTALL_PREFIX}/include/ncnn")

if(USE_SYSTEM_NCNN)
    # ── Системна бібліотека ─────────────────────────────────────────────────
    find_package(ncnn REQUIRED)
    message(STATUS "[Ncnn] Системна: ncnn")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(ncnn QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(ncnn_FOUND)
        message(STATUS "[Ncnn] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")
        # Якщо find_package дав target 'ncnn' без namespace — додаємо аліас
        if(TARGET ncnn AND NOT TARGET ncnn::ncnn)
            add_library(ncnn::ncnn ALIAS ncnn)
        endif()

    else()
        message(STATUS "[Ncnn] Буде зібрано з джерел (${NCNN_VERSION})")

        ep_cmake_args(_ncnn_cmake_args
            -DNCNN_BUILD_TESTS=OFF
            -DNCNN_BUILD_EXAMPLES=OFF
            -DNCNN_BUILD_BENCHMARK=OFF
            -DNCNN_BUILD_TOOLS=OFF
            # Vulkan: вимкнено (RPi не має підтримки Vulkan за замовч.)
            -DNCNN_VULKAN=OFF
            # Shared library
            -DNCNN_SHARED_LIB=ON
            -DNCNN_ENABLE_LTO=OFF
        )

        ExternalProject_Add(ncnn_ep
            GIT_REPOSITORY      "${NCNN_GIT_REPO}"
            GIT_TAG             "${NCNN_VERSION}"
            GIT_SHALLOW         ON
            GIT_SUBMODULES_RECURSE ON
            SOURCE_DIR          "${EP_SOURCES_DIR}/ncnn"
            CMAKE_ARGS      ${_ncnn_cmake_args}
            BUILD_BYPRODUCTS "${_ncnn_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(ncnn::ncnn ncnn_ep "${_ncnn_lib}" "${_ncnn_inc}")
    endif()
endif()

unset(_ncnn_lib)
unset(_ncnn_inc)
