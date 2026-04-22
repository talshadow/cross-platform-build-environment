# cmake/external/PhySys.cmake
#
# PhysicsFS — портабельна абстракція файлової системи для ігор та застосунків.
# Надає уніфікований доступ до архівів ZIP, 7z, ISO та інших як до файлової системи.
# https://github.com/icculus/physfs
#
# Provides imported target:
#   PhysicsFS::PhysicsFS  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_PHYSYS  — ON: find_package / OFF (default): ExternalProject
#
# Кеш-змінні:
#   PHYSYS_VERSION, PHYSYS_GIT_REPO

option(USE_SYSTEM_PHYSYS
    "Використовувати системну PhysicsFS замість збірки з джерел"
    OFF)

set(PHYSYS_VERSION "release-3.2.0"
    CACHE STRING "Версія PhysicsFS для збірки з джерел")

set(PHYSYS_GIT_REPO
    "https://github.com/icculus/physfs.git"
    CACHE STRING "Git репозиторій PhysicsFS")

# ---------------------------------------------------------------------------

set(_physfs_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libphysfs.so")
set(_physfs_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_PHYSYS)
    # ── Системна бібліотека ─────────────────────────────────────────────────
    find_package(PhysicsFS REQUIRED)
    message(STATUS "[PhysicsFS] Системна: PhysicsFS::PhysicsFS")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(PhysicsFS QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(PhysicsFS_FOUND)
        message(STATUS "[PhysicsFS] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_physfs_lib}")
        ep_imported_library(PhysicsFS::PhysicsFS "${_physfs_lib}" "${_physfs_inc}")
        message(STATUS "[PhysicsFS] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[PhysicsFS] Буде зібрано з джерел (${PHYSYS_VERSION})")

        ep_cmake_args(_physfs_cmake_args
            -DPHYSFS_BUILD_STATIC=OFF
            -DPHYSFS_BUILD_SHARED=ON
            -DPHYSFS_BUILD_TEST=OFF
            -DPHYSFS_BUILD_DOCS=OFF
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        )

        ExternalProject_Add(physfs_ep
            GIT_REPOSITORY  "${PHYSYS_GIT_REPO}"
            GIT_TAG         "${PHYSYS_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/physfs"
            CMAKE_ARGS      ${_physfs_cmake_args}
            BUILD_BYPRODUCTS "${_physfs_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(
            PhysicsFS::PhysicsFS physfs_ep "${_physfs_lib}" "${_physfs_inc}")
        ep_track_cmake_file(physfs_ep "${CMAKE_CURRENT_LIST_FILE}")
    endif()
endif()

unset(_physfs_lib)
unset(_physfs_inc)
