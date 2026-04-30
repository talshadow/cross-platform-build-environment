# cmake/modules/InstallHelpers.cmake
#
# target_add_ep_rpath(<target>)
#   Вбудовує $ORIGIN/../lib RPATH у <target> — так само як EP-бібліотеки.
#
# project_setup_install(<target>)
#   Налаштовує кастомну інсталяцію головного виконуваного файлу.
#
# Створює цілі:
#
#   install_<target>
#     Копіює <target> та всі EP/toolchain залежності у:
#       ${CMAKE_BINARY_DIR}/install_<BUILD_TYPE>/
#         bin/  — виконуваний файл
#         lib/  — shared libraries (EP + toolchain)
#
#   install_<target>_stripped          [тільки RelWithDebInfo]
#     Те саме, але з --strip-all (bin) та --strip-debug (libs):
#       ${CMAKE_BINARY_DIR}/install_RelWithDebInfo_stripped/
#
# Залежності та структура директорій визначаються через GNUInstallDirs.
# Аналіз бінарних залежностей виконується ep_check_binary_deps (BinaryDeps.cmake)
# у момент запуску цілі (після збірки), а не під час конфігурації.
#
# Використання:
#   # (автоматично підключається з BuildConfig.cmake)
#   project_setup_install(opencv_example)
#   # → створює: install_opencv_example, install_opencv_example_stripped (RelWithDebInfo)

include(GNUInstallDirs)
include(RuntimeDeps)

# ---------------------------------------------------------------------------
# target_add_ep_rpath(<target>)
#
# Додає $ORIGIN/../lib до INSTALL_RPATH таргету — так само як EP-бібліотеки
# (через ep_cmake_args у Common.cmake).
#
# Використовує APPEND, тому безпечно якщо INSTALL_RPATH вже задано.
#
# Використання:
#   target_link_libraries(my_app PRIVATE PNG::PNG OpenCV::opencv_core)
#   target_add_ep_rpath(my_app)
# ---------------------------------------------------------------------------
function(target_add_ep_rpath target)
    if(NOT TARGET "${target}")
        message(FATAL_ERROR "[InstallHelpers] target_add_ep_rpath: target '${target}' не існує")
    endif()
    set_property(TARGET "${target}" APPEND PROPERTY
        INSTALL_RPATH "$ORIGIN/../lib")
    set_target_properties("${target}" PROPERTIES
        BUILD_WITH_INSTALL_RPATH    ON
        INSTALL_RPATH_USE_LINK_PATH OFF
    )
endfunction()

function(project_setup_install target)
    if(NOT TARGET "${target}")
        message(FATAL_ERROR "[InstallHelpers] Target '${target}' не існує")
    endif()

    set(_script "${CMAKE_SOURCE_DIR}/cmake/install_project.cmake")
    if(NOT EXISTS "${_script}")
        message(FATAL_ERROR "[InstallHelpers] Скрипт не знайдено: ${_script}")
    endif()

    # Визначаємо тип збірки (для single-config генераторів)
    set(_build_type "${CMAKE_BUILD_TYPE}")
    if(_build_type STREQUAL "")
        set(_build_type "unknown")
    endif()

    # Збираємо runtime-ресурси (IPA модулі, configs, data) транзитивно по
    # LINK_LIBRARIES. Результат записується у cmake-файл і передається у
    # install_project.cmake де виконується копіювання і ре-підпис.
    ep_collect_runtime_resources(${target} _rt_file)

    # Аргументи, спільні для обох цілей
    # Змінні часу конфігурації запікаються у рядок; шляхи з пробілами
    # коректно передаються завдяки VERBATIM у add_custom_target.
    set(_common_defs
        "-DCMAKE_MODULE_PATH=${CMAKE_SOURCE_DIR}/cmake/modules"
        "-DEXTERNAL_INSTALL_PREFIX=${EXTERNAL_INSTALL_PREFIX}"
        "-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}"
        "-DCMAKE_READELF=${CMAKE_READELF}"
        "-DCMAKE_STRIP=${CMAKE_STRIP}"
        "-DCMAKE_SYSROOT=${CMAKE_SYSROOT}"
        "-DINSTALL_BINDIR=${CMAKE_INSTALL_BINDIR}"
        "-DINSTALL_LIBDIR=${CMAKE_INSTALL_LIBDIR}"
        "-DRUNTIME_RESOURCES_FILE=${_rt_file}"
    )

    # ── install_<target> ─────────────────────────────────────────────────────
    set(_prefix "${CMAKE_BINARY_DIR}/install_${_build_type}")

    add_custom_target(install_${target}
        COMMAND ${CMAKE_COMMAND}
            "-DBINARY_FILE=$<TARGET_FILE:${target}>"
            "-DINSTALL_PREFIX=${_prefix}"
            "-DDO_STRIP=OFF"
            ${_common_defs}
            -P "${_script}"
        DEPENDS "${target}"
        COMMENT "Installing ${target} → install_${_build_type}/"
        VERBATIM
    )

    message(STATUS "[InstallHelpers] Ціль 'install_${target}' → ${_prefix}/")

    # ── install_<target>_stripped (тільки RelWithDebInfo) ───────────────────
    if(_build_type STREQUAL "RelWithDebInfo")
        set(_stripped_prefix "${CMAKE_BINARY_DIR}/install_RelWithDebInfo_stripped")

        add_custom_target(install_${target}_stripped
            COMMAND ${CMAKE_COMMAND}
                "-DBINARY_FILE=$<TARGET_FILE:${target}>"
                "-DINSTALL_PREFIX=${_stripped_prefix}"
                "-DDO_STRIP=ON"
                ${_common_defs}
                -P "${_script}"
            DEPENDS "${target}"
            COMMENT "Installing ${target} (stripped) → install_RelWithDebInfo_stripped/"
            VERBATIM
        )

        message(STATUS "[InstallHelpers] Ціль 'install_${target}_stripped' → ${_stripped_prefix}/")
    endif()
endfunction()
