# cmake/external/OneTBB.cmake
#
# oneTBB — Intel Threading Building Blocks, паралельне програмування для C++
# https://github.com/uxlfoundation/oneTBB
#
# Provides imported targets:
#   TBB::tbb        — SHARED IMPORTED
#   TBB::tbbmalloc  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_ONETBB  — ON: find_package в системі/sysroot
#                        OFF (за замовченням): зібрати через ExternalProject
#   ONETBB_USE_GIT     — ON: git clone / OFF (за замовченням): архів з GitHub Releases
#
# Кеш-змінні:
#   ONETBB_VERSION   — версія (без префіксу v)
#   ONETBB_GIT_REPO  — URL git репозиторію (тільки при ONETBB_USE_GIT=ON)

option(USE_SYSTEM_ONETBB
    "Використовувати системний oneTBB (find_package) замість збірки з джерел"
    OFF)

option(ONETBB_USE_GIT
    "Завантажувати oneTBB через git clone (OFF = архів з GitHub Releases)"
    OFF)

set(ONETBB_VERSION  "2022.3.0"
    CACHE STRING "Версія oneTBB для збірки з джерел")

set(ONETBB_GIT_REPO
    "https://github.com/uxlfoundation/oneTBB.git"
    CACHE STRING "Git репозиторій oneTBB (використовується тільки при ONETBB_USE_GIT=ON)")

# ---------------------------------------------------------------------------

set(_tbb_lib        "${EXTERNAL_INSTALL_PREFIX}/lib/libtbb.so")
set(_tbbmalloc_lib  "${EXTERNAL_INSTALL_PREFIX}/lib/libtbbmalloc.so")
set(_tbb_inc        "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_ONETBB)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(TBB REQUIRED)
    message(STATUS "[oneTBB] Системна бібліотека версії ${TBB_VERSION}")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(TBB QUIET HINTS "${EXTERNAL_INSTALL_PREFIX}" NO_DEFAULT_PATH)
    if(TBB_FOUND)
        message(STATUS "[oneTBB] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_tbb_lib}")
        ep_imported_library(TBB::tbb       "${_tbb_lib}"       "${_tbb_inc}")
        ep_imported_library(TBB::tbbmalloc "${_tbbmalloc_lib}" "${_tbb_inc}")
        message(STATUS "[oneTBB] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[oneTBB] Буде зібрано з джерел (версія ${ONETBB_VERSION})")

        if(ONETBB_USE_GIT)
            message(STATUS "[oneTBB] Джерело: git clone (${ONETBB_GIT_REPO})")
            set(_tbb_download_args
                GIT_REPOSITORY  "${ONETBB_GIT_REPO}"
                GIT_TAG         "v${ONETBB_VERSION}"
                GIT_SHALLOW     ON
            )
        else()
            set(_tbb_archive_url
                "https://github.com/uxlfoundation/oneTBB/archive/refs/tags/v${ONETBB_VERSION}.tar.gz")
            message(STATUS "[oneTBB] Джерело: архів (${_tbb_archive_url})")
            set(_tbb_download_args
                URL                 "${_tbb_archive_url}"
                DOWNLOAD_EXTRACT_TIMESTAMP ON
            )
            unset(_tbb_archive_url)
        endif()

        ep_cmake_args(_tbb_cmake_args
            -DTBB_TEST=OFF
            -DTBB_EXAMPLES=OFF
            -DTBB_STRICT=OFF
        )

        ExternalProject_Add(onetbb_ep
            ${_tbb_download_args}
            SOURCE_DIR      "${EP_SOURCES_DIR}/onetbb"
            CMAKE_ARGS      ${_tbb_cmake_args}
            BUILD_BYPRODUCTS
                "${_tbb_lib}"
                "${_tbbmalloc_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(TBB::tbb       onetbb_ep "${_tbb_lib}"       "${_tbb_inc}")
        ep_imported_library_from_ep(TBB::tbbmalloc onetbb_ep "${_tbbmalloc_lib}" "${_tbb_inc}")
        ep_track_cmake_file(onetbb_ep "${CMAKE_CURRENT_LIST_FILE}")

        if(ONETBB_USE_GIT)
            ep_prestamp_git(onetbb_ep "${EP_SOURCES_DIR}/onetbb" "v${ONETBB_VERSION}")
        endif()
    endif()
endif()

unset(_tbb_lib)
unset(_tbbmalloc_lib)
unset(_tbb_inc)
