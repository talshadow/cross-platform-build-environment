# cmake/external/AirSim.cmake
#
# AirSim (Microsoft) — симулятор безпілотних апаратів та роботів з
# фотореалістичним рендерингом (Unreal Engine). Ця бібліотека надає
# C++ клієнт (AirLib) для з'єднання з AirSim сервером через RPC.
# https://github.com/microsoft/AirSim
#
# Provides imported target:
#   AirSim::AirLib  — SHARED IMPORTED
#
# Примітки:
#   - Збирається тільки клієнтська частина (без Unreal Engine).
#   - Залежить від rpclib (bundled), Eigen3, OpenCV (опційно).
#   - AirSim архівований Microsoft у 2023 році; остання версія v1.8.1.
#
# Опції:
#   USE_SYSTEM_AIRSIM  — ON: find_package / OFF (default): ExternalProject
#
# Кеш-змінні:
#   AIRSIM_VERSION, AIRSIM_URL, AIRSIM_URL_HASH

option(USE_SYSTEM_AIRSIM
    "Використовувати системну AirSim замість збірки з джерел"
    OFF)

set(AIRSIM_VERSION "v1.8.1"
    CACHE STRING "Версія AirSim для збірки з джерел")

set(AIRSIM_URL
    "https://github.com/microsoft/AirSim/archive/refs/tags/${AIRSIM_VERSION}.tar.gz"
    CACHE STRING "URL архіву AirSim")

set(AIRSIM_URL_HASH ""
    CACHE STRING "SHA256 хеш архіву AirSim (порожньо = не перевіряти)")

# ---------------------------------------------------------------------------

set(_airsim_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libAirLib.so")
set(_airsim_inc "${EXTERNAL_INSTALL_PREFIX}/include/AirSim")

if(USE_SYSTEM_AIRSIM)
    # ── Системна бібліотека ─────────────────────────────────────────────────
    find_package(AirSim REQUIRED
        HINTS "${CMAKE_SYSROOT}/usr" "${CMAKE_SYSROOT}/usr/local")
    message(STATUS "[AirSim] Системна: AirSim::AirLib")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(AirSim QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(AirSim_FOUND)
        message(STATUS "[AirSim] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_airsim_lib}")
        ep_imported_library(AirSim::AirLib "${_airsim_lib}" "${_airsim_inc}")
        message(STATUS "[AirSim] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[AirSim] Буде зібрано з джерел (${AIRSIM_VERSION})")

        set(_hash_arg "")
        if(AIRSIM_URL_HASH)
            set(_hash_arg URL_HASH "SHA256=${AIRSIM_URL_HASH}")
        endif()

        # AirSim передає Eigen через bundled — тому явно вказуємо наш
        set(_airsim_eigen_inc "")
        if(TARGET Eigen3::Eigen)
            get_target_property(_airsim_eigen_inc Eigen3::Eigen INTERFACE_INCLUDE_DIRECTORIES)
        endif()
        if(NOT _airsim_eigen_inc)
            set(_airsim_eigen_inc "${EXTERNAL_INSTALL_PREFIX}/include")
        endif()

        _ep_collect_deps(_airsim_ep_deps eigen3_ep)

        ep_cmake_args(_airsim_cmake_args
            # Збираємо тільки AirLib (клієнт), без прикладів
            -DBUILD_EXAMPLES=OFF
            # Використовуємо наш Eigen
            -DEIGEN3_INCLUDE_DIR=${_airsim_eigen_inc}
            # rpclib — bundled всередині AirSim (external/rpclib/),
            # не встановлюється в EXTERNAL_INSTALL_PREFIX, не потребує явного шляху
        )

        ExternalProject_Add(airsim_ep
            URL             "${AIRSIM_URL}"
            ${_hash_arg}
            DOWNLOAD_DIR    "${EP_SOURCES_DIR}/airsim"
            SOURCE_SUBDIR   "cmake"
            CMAKE_ARGS      ${_airsim_cmake_args}
            DEPENDS         ${_airsim_ep_deps}
            BUILD_BYPRODUCTS "${_airsim_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(AirSim::AirLib airsim_ep "${_airsim_lib}" "${_airsim_inc}")

        unset(_airsim_eigen_inc)
        unset(_airsim_ep_deps)
    endif()
endif()

unset(_airsim_lib)
unset(_airsim_inc)
