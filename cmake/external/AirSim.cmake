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
#   AIRSIM_VERSION, AIRSIM_GIT_REPO

option(USE_SYSTEM_AIRSIM
    "Використовувати системну AirSim замість збірки з джерел"
    OFF)

set(AIRSIM_VERSION "v1.8.1"
    CACHE STRING "Версія AirSim для збірки з джерел")

set(AIRSIM_GIT_REPO
    "https://github.com/microsoft/AirSim.git"
    CACHE STRING "Git репозиторій AirSim")

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

        # AirSim передає Eigen через bundled — тому явно вказуємо наш
        set(_airsim_eigen_inc "")
        if(TARGET Eigen3::Eigen)
            get_target_property(_airsim_eigen_inc Eigen3::Eigen INTERFACE_INCLUDE_DIRECTORIES)
        endif()
        if(NOT _airsim_eigen_inc)
            set(_airsim_eigen_inc "${EXTERNAL_INSTALL_PREFIX}/include")
        endif()

        ep_cmake_args(_airsim_cmake_args
            # Збираємо тільки AirLib (клієнт), без прикладів
            -DBUILD_EXAMPLES=OFF
            # Використовуємо наш Eigen
            -DEIGEN3_INCLUDE_DIR=${_airsim_eigen_inc}
            # rpclib — bundled всередині AirSim (external/rpclib/),
            # не встановлюється в EXTERNAL_INSTALL_PREFIX, не потребує явного шляху
            # Сумісність з cmake_minimum_required < 3.5 у MavLinkCom
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5
            # MavLinkCom не включає <cstdint> явно — не компілюється на GCC 13+.
            # -include змушує компілятор додати #include на початку кожного TU.
            "-DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS} -include cstdint"
            # AirSim CommonSetup.cmake шукає AIRSIM_ROOT через find_path з відносними
            # шляхами. З CMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY ці шляхи трансформуються
            # sysroot-префіксом і не знаходяться. Передаємо явно щоб find_path пропустив пошук.
            -DAIRSIM_ROOT=${EP_SOURCES_DIR}/airsim
        )

    ExternalProject_Add(airsim_ep
        GIT_REPOSITORY      "${AIRSIM_GIT_REPO}"
        GIT_TAG             "${AIRSIM_VERSION}"
        GIT_SUBMODULES_RECURSE ON
        SOURCE_DIR          "${EP_SOURCES_DIR}/airsim"
        # Після клонування:
        # 1. Симлінкуємо вихідники rpclib у місце, де AirSim їх шукає.
        #    AirSim будує rpclib через add_subdirectory — не через find_package.
        # 2. Патчимо IncludeEigen() у CommonSetup.cmake: AirSim хардкодить
        #    шлях до bundled eigen3 (AirLib/deps/eigen3), якого немає в repo.
        #    Замінюємо на наш EXTERNAL_INSTALL_PREFIX/include/eigen3.
        PATCH_COMMAND
        ${CMAKE_COMMAND} -E make_directory
        "${EP_SOURCES_DIR}/airsim/external/rpclib"
        COMMAND ${CMAKE_COMMAND} -E rm -f
        "${EP_SOURCES_DIR}/airsim/external/rpclib/rpclib-2.3.0"
        COMMAND ${CMAKE_COMMAND} -E create_symlink
        "${EP_SOURCES_DIR}/rpclib"
        "${EP_SOURCES_DIR}/airsim/external/rpclib/rpclib-2.3.0"
        COMMAND sed -i
        "s|include_directories(.*deps/eigen3.*)|include_directories(${_airsim_eigen_inc})|g"
        "${EP_SOURCES_DIR}/airsim/cmake/cmake-modules/CommonSetup.cmake"
        # AirLib хардкодить STATIC — замінюємо на SHARED.
        # MavLinkCom/rpclib лишаються STATIC; компілюються з -fPIC
        # (CommonSetup встановлює CMAKE_POSITION_INDEPENDENT_CODE ON),
        # тому линкуються у libAirLib.so без проблем.
        COMMAND sed -i
        "s|add_library(\${PROJECT_NAME} STATIC|add_library(\${PROJECT_NAME} SHARED|g"
            "${EP_SOURCES_DIR}/airsim/cmake/AirLib/CMakeLists.txt"
            SOURCE_SUBDIR   "cmake"
            CMAKE_ARGS      ${_airsim_cmake_args}
            # AirSim не має install() — копіюємо вручну
            INSTALL_COMMAND
            ${CMAKE_COMMAND} -E copy
            "<BINARY_DIR>/output/lib/libAirLib.so"
            "${_airsim_lib}"
            COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${EP_SOURCES_DIR}/airsim/AirLib/include"
            "${_airsim_inc}"
            BUILD_BYPRODUCTS "${_airsim_lib}"
            LOG_DOWNLOAD    ON
            LOG_CONFIGURE   ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

    ep_imported_library_from_ep(AirSim::AirLib airsim_ep "${_airsim_lib}" "${_airsim_inc}")
    ep_track_cmake_file(airsim_ep "${CMAKE_CURRENT_LIST_FILE}")

    unset(_airsim_eigen_inc)
    unset(_airsim_ep_deps)
endif()
endif()

unset(_airsim_lib)
unset(_airsim_inc)
