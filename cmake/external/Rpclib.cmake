# cmake/external/Rpclib.cmake
#
# rpclib — сучасна C++14 бібліотека для msgpack-RPC.
# Використовується як залежність AirSim (AirLib клієнт).
# https://github.com/rpclib/rpclib
#
# Provides imported target:
#   rpclib::rpc  — SHARED IMPORTED
#
# Примітки:
#   - Крім надання rpclib::rpc, також зберігає вихідники у EP_SOURCES_DIR/rpclib,
#     що дозволяє AirSim включати rpclib як add_subdirectory через симлінк.
#
# Опції:
#   USE_SYSTEM_RPCLIB  — ON: find_package / OFF (default): ExternalProject
#
# Кеш-змінні:
#   RPCLIB_VERSION, RPCLIB_GIT_REPO

option(USE_SYSTEM_RPCLIB
    "Використовувати системну rpclib замість збірки з джерел"
    OFF)

set(RPCLIB_VERSION "v2.3.0"
    CACHE STRING "Версія rpclib для збірки з джерел")

set(RPCLIB_GIT_REPO
    "https://github.com/rpclib/rpclib.git"
    CACHE STRING "Git репозиторій rpclib")

# ---------------------------------------------------------------------------

set(_rpclib_lib "${EXTERNAL_INSTALL_PREFIX}/lib/librpc.so")
set(_rpclib_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_RPCLIB)
    # ── Системна бібліотека ─────────────────────────────────────────────────
    find_package(rpclib REQUIRED
        HINTS "${CMAKE_SYSROOT}/usr" "${CMAKE_SYSROOT}/usr/local")
    message(STATUS "[Rpclib] Системна: rpclib::rpc")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(rpclib QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(rpclib_FOUND)
        message(STATUS "[Rpclib] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_rpclib_lib}")
        ep_imported_library(rpclib::rpc "${_rpclib_lib}" "${_rpclib_inc}")
        message(STATUS "[Rpclib] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[Rpclib] Буде зібрано з джерел (${RPCLIB_VERSION})")

        ep_cmake_args(_rpclib_cmake_args
            -DRPCLIB_BUILD_TESTS=OFF
            -DRPCLIB_GENERATE_COMPDB=OFF
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        )

        ExternalProject_Add(rpclib_ep
            GIT_REPOSITORY  "${RPCLIB_GIT_REPO}"
            GIT_TAG         "${RPCLIB_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/rpclib"
            CMAKE_ARGS      ${_rpclib_cmake_args}
            BUILD_BYPRODUCTS "${_rpclib_lib}"
            LOG_DOWNLOAD    ON
            LOG_CONFIGURE   ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(rpclib::rpc rpclib_ep "${_rpclib_lib}" "${_rpclib_inc}")
        ep_track_cmake_file(rpclib_ep "${CMAKE_CURRENT_LIST_FILE}")
    endif()
endif()

unset(_rpclib_lib)
unset(_rpclib_inc)
