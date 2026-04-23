# cmake/external/EasyProfiler.cmake
#
# easy_profiler — легкий інструментований C++ профілювальник.
# Надає макроси для вимірювання часу блоків коду та GUI-переглядач.
# https://github.com/yse/easy_profiler
#
# Provides imported target:
#   easy_profiler::easy_profiler  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_EASYPROFILER  — ON: find_package / OFF (default): ExternalProject
#
# Кеш-змінні:
#   EASYPROFILER_VERSION, EASYPROFILER_GIT_REPO

option(USE_SYSTEM_EASYPROFILER
    "Використовувати системну easy_profiler замість збірки з джерел"
    OFF)

set(EASYPROFILER_VERSION "v2.1.0"
    CACHE STRING "Версія easy_profiler для збірки з джерел")

set(EASYPROFILER_GIT_REPO
    "https://github.com/yse/easy_profiler.git"
    CACHE STRING "Git репозиторій easy_profiler")

# ---------------------------------------------------------------------------

set(_ep_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libeasy_profiler.so")
set(_ep_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_EASYPROFILER)
    # ── Системна бібліотека ─────────────────────────────────────────────────
    find_package(easy_profiler REQUIRED)
    message(STATUS "[EasyProfiler] Системна: easy_profiler::easy_profiler")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(easy_profiler QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(easy_profiler_FOUND)
        message(STATUS "[EasyProfiler] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")
        # easy_profiler деяких версій не експортує namespaced target через cmake config —
        # гарантуємо існування easy_profiler::easy_profiler незалежно від якості конфіга.
        if(NOT TARGET easy_profiler::easy_profiler)
            ep_imported_library(easy_profiler::easy_profiler "${_ep_lib}" "${_ep_inc}")
        endif()

    elseif(EXISTS "${_ep_lib}")
        ep_imported_library(easy_profiler::easy_profiler "${_ep_lib}" "${_ep_inc}")
        message(STATUS "[EasyProfiler] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[EasyProfiler] Буде зібрано з джерел (${EASYPROFILER_VERSION})")

        ep_cmake_args(_ep_cmake_args
            -DEASY_PROFILER_NO_GUI=ON
            -DEASY_PROFILER_NO_SAMPLES=ON
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        )

        ExternalProject_Add(easyprofiler_ep
            GIT_REPOSITORY  "${EASYPROFILER_GIT_REPO}"
            GIT_TAG         "${EASYPROFILER_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/easyprofiler"
            CMAKE_ARGS      ${_ep_cmake_args}
            BUILD_BYPRODUCTS "${_ep_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(
            easy_profiler::easy_profiler easyprofiler_ep "${_ep_lib}" "${_ep_inc}")
        ep_track_cmake_file(easyprofiler_ep "${CMAKE_CURRENT_LIST_FILE}")
    endif()
endif()

unset(_ep_lib)
unset(_ep_inc)
