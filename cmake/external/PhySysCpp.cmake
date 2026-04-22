# cmake/external/PhySysCpp.cmake
#
# physfs-hpp — header-only C++ обгортка для PhysicsFS.
# Надає RAII-класи та ітератори поверх C API PhysicsFS.
# https://github.com/Lectem/physfs-hpp
#
# Provides imported target:
#   physfs-hpp::physfs-hpp  — INTERFACE IMPORTED (header-only)
#
# Залежності:
#   - PhysicsFS::PhysicsFS (physfs_ep)
#
# Опції:
#   USE_SYSTEM_PHYSYSCPP  — ON: find_package / OFF (default): ExternalProject
#
# Кеш-змінні:
#   PHYSYSCPP_VERSION, PHYSYSCPP_GIT_REPO

option(USE_SYSTEM_PHYSYSCPP
    "Використовувати системну physfs-hpp замість збірки з джерел"
    OFF)

set(PHYSYSCPP_VERSION "master"
    CACHE STRING "Версія physfs-hpp для збірки з джерел")

set(PHYSYSCPP_GIT_REPO
    "https://github.com/Ybalrid/physfs-hpp.git"
    CACHE STRING "Git репозиторій physfs-hpp")

# ---------------------------------------------------------------------------

set(_physfscpp_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_PHYSYSCPP)
    # ── Системна бібліотека ─────────────────────────────────────────────────
    find_package(physfs-hpp REQUIRED
        HINTS "${CMAKE_SYSROOT}/usr" "${CMAKE_SYSROOT}/usr/local")
    message(STATUS "[PhysFSCpp] Системна: physfs-hpp::physfs-hpp")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(physfs-hpp QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(physfs-hpp_FOUND)
        message(STATUS "[PhysFSCpp] Знайдено готові заголовки у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_physfscpp_inc}/physfs.hpp")
        ep_imported_interface(physfs-hpp::physfs-hpp "${_physfscpp_inc}")
        message(STATUS "[PhysFSCpp] Знайдено заголовки у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[PhysFSCpp] Буде встановлено з джерел (${PHYSYSCPP_VERSION})")

        # physfs-hpp — header-only, cmake не потрібен.
        # Просто копіюємо physfs.hpp після клонування.
        ExternalProject_Add(physfscpp_ep
            GIT_REPOSITORY    "${PHYSYSCPP_GIT_REPO}"
            GIT_TAG           "${PHYSYSCPP_VERSION}"
            GIT_SHALLOW       ON
            SOURCE_DIR        "${EP_SOURCES_DIR}/physfscpp"
            CONFIGURE_COMMAND ""
            BUILD_COMMAND     ""
            INSTALL_COMMAND
                ${CMAKE_COMMAND} -E copy
                    "${EP_SOURCES_DIR}/physfscpp/include/physfs.hpp"
                    "${EXTERNAL_INSTALL_PREFIX}/include/physfs.hpp"
            BUILD_BYPRODUCTS  "${_physfscpp_inc}/physfs.hpp"
            LOG_DOWNLOAD      ON
            LOG_INSTALL       ON
        )

        ep_imported_interface_from_ep(
            physfs-hpp::physfs-hpp physfscpp_ep "${_physfscpp_inc}")
        ep_track_cmake_file(physfscpp_ep "${CMAKE_CURRENT_LIST_FILE}")

        unset(_physfscpp_ep_deps)
    endif()
endif()

unset(_physfscpp_inc)
