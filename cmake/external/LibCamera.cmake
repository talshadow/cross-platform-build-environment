# cmake/external/LibCamera.cmake
#
# libcamera — відкрита бібліотека для роботи з камерами (v4l2, ISP, Raspberry Pi).
# https://libcamera.org/
#
# Provides imported target:
#   libcamera::libcamera  — SHARED IMPORTED
#
# Примітки:
#   - Збірка вимагає python3-yaml та python3-ply (генератор IPA) на хості.
#   - USE_SYSTEM_LIBCAMERA=ON (за замовч.) — знайти встановлену системну бібліотеку
#     або з sysroot. При крос-компіляції libcamera зазвичай постачається
#     разом з BSP/sysroot (Raspberry Pi OS, Yocto).
#   - USE_SYSTEM_LIBCAMERA=OFF — зібрати з джерел через Meson.
#     Потребує meson та ninja в PATH хоста.
#
# Опції:
#   USE_SYSTEM_LIBCAMERA  — ON (за замовч.): find_package / pkg-config
#                           OFF: зібрати через Meson ExternalProject
#
# Кеш-змінні:
#   LIBCAMERA_VERSION, LIBCAMERA_GIT_REPO

option(USE_SYSTEM_LIBCAMERA
    "Використовувати системну libcamera замість збірки з джерел (рекомендовано)"
    OFF)

set(LIBCAMERA_VERSION "v0.5.2+rpt20250903"
    CACHE STRING "Версія libcamera для збірки з джерел")

set(LIBCAMERA_GIT_REPO
    "https://github.com/raspberrypi/libcamera.git"
    CACHE STRING "Git репозиторій libcamera (Raspberry Pi форк)")

# ---------------------------------------------------------------------------

set(_libcamera_lib      "${EXTERNAL_INSTALL_PREFIX}/lib/libcamera.so")
set(_libcamera_base_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libcamera-base.so")
set(_libcamera_inc      "${EXTERNAL_INSTALL_PREFIX}/include")

# libcamera складається з двох бібліотек: libcamera-base.so (Thread, EventDispatcher тощо)
# та libcamera.so. Цей макрос створює обидва IMPORTED таргети і прописує залежність
# libcamera::libcamera → libcamera::libcamera-base.
macro(_libcamera_make_base_target ep_name_or_empty)
    if(ep_name_or_empty AND TARGET ${ep_name_or_empty})
        ep_imported_library_from_ep(
            libcamera::libcamera-base ${ep_name_or_empty}
            "${_libcamera_base_lib}" "${_libcamera_inc}")
    else()
        ep_imported_library(
            libcamera::libcamera-base
            "${_libcamera_base_lib}" "${_libcamera_inc}")
    endif()
    set_property(TARGET libcamera::libcamera APPEND PROPERTY
        INTERFACE_LINK_LIBRARIES libcamera::libcamera-base)
endmacro()

if(USE_SYSTEM_LIBCAMERA)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(libcamera QUIET)
    if(libcamera_FOUND)
        message(STATUS "[LibCamera] Системна: libcamera::libcamera")
    else()
        # Fallback: pkg-config
        find_package(PkgConfig QUIET)
        if(PkgConfig_FOUND)
            pkg_check_modules(LIBCAMERA IMPORTED_TARGET libcamera)
            if(LIBCAMERA_FOUND)
                if(NOT TARGET libcamera::libcamera)
                    # ALIAS не підходить для non-GLOBAL IMPORTED target (до CMake 3.24).
                    # Створюємо INTERFACE IMPORTED GLOBAL та делегуємо на PkgConfig::LIBCAMERA.
                    add_library(libcamera::libcamera INTERFACE IMPORTED GLOBAL)
                    set_property(TARGET libcamera::libcamera
                        APPEND PROPERTY INTERFACE_LINK_LIBRARIES PkgConfig::LIBCAMERA)
                endif()
                message(STATUS "[LibCamera] Системна (pkg-config): ${LIBCAMERA_LIBRARIES}")
            else()
                message(WARNING "[LibCamera] USE_SYSTEM_LIBCAMERA=ON але libcamera не знайдено. "
                    "Встановіть libcamera-dev або передайте USE_SYSTEM_LIBCAMERA=OFF "
                    "та зберіть з джерел (потрібні meson, ninja, python3-yaml, python3-ply).")
            endif()
        else()
            message(WARNING "[LibCamera] USE_SYSTEM_LIBCAMERA=ON але libcamera не знайдено "
                "(pkg-config недоступний). Встановіть libcamera-dev.")
        endif()
    endif()

else()
    # ── Алгоритм: find_package → ExternalProject_Add (Meson) ───────────────
    find_package(libcamera QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(libcamera_FOUND)
        message(STATUS "[LibCamera] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_libcamera_lib}")
        # libcamera не має LibcameraConfig.cmake — перевіряємо .so напряму.
        # RPi-форк встановлює згенеровані IPA-заголовки у include/libcamera/libcamera/
        # замість include/libcamera/ — виправляємо на місці при конфігурації.
        set(_lc_nested "${EXTERNAL_INSTALL_PREFIX}/include/libcamera/libcamera")
        if(IS_DIRECTORY "${_lc_nested}")
            file(GLOB _lc_nested_items LIST_DIRECTORIES true "${_lc_nested}/*")
            foreach(_item ${_lc_nested_items})
                file(COPY "${_item}" DESTINATION "${EXTERNAL_INSTALL_PREFIX}/include/libcamera")
            endforeach()
            file(REMOVE_RECURSE "${_lc_nested}")
            message(STATUS "[LibCamera] Виправлено подвійне вкладення include/libcamera/libcamera → include/libcamera")
        endif()
        unset(_lc_nested_items)
        unset(_lc_nested)
        # libcamera.pc / libcamera-base.pc мають Cflags: -I${includedir}/libcamera.
        # Це ламає #include <libcamera/base/span.h> у споживачах (rpicam-apps тощо):
        # pkg-config дає -I.../include/libcamera, тоді libcamera/base/span.h шукається
        # у include/libcamera/libcamera/base/span.h — якого немає після flatten.
        # Виправляємо на -I${includedir} щоб include/libcamera/base/span.h знаходилось.
        set(_dollar "$")
        foreach(_lc_pc_name libcamera libcamera-base)
            set(_lc_pc "${EXTERNAL_INSTALL_PREFIX}/lib/pkgconfig/${_lc_pc_name}.pc")
            if(EXISTS "${_lc_pc}")
                file(READ "${_lc_pc}" _lc_pc_content)
                string(REPLACE
                    "Cflags: -I${_dollar}{includedir}/libcamera"
                    "Cflags: -I${_dollar}{includedir}"
                    _lc_pc_content "${_lc_pc_content}")
                file(WRITE "${_lc_pc}" "${_lc_pc_content}")
            endif()
        endforeach()
        unset(_lc_pc)
        unset(_lc_pc_content)
        unset(_lc_pc_name)
        unset(_dollar)
        ep_imported_library(libcamera::libcamera "${_libcamera_lib}" "${_libcamera_inc}")
        _libcamera_make_base_target("")
        message(STATUS "[LibCamera] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[LibCamera] Буде зібрано з джерел (${LIBCAMERA_VERSION}) через Meson")

        _ep_require_meson()
        # yaml та ply — host-tools для генератора IPA protocol (не target-залежності).
        # Безпечні при cross-build: виконуються на хості, не потрапляють у sysroot.
        _ep_require_python_modules(yaml ply)
        find_program(_libcamera_meson meson)
        find_program(_libcamera_ninja ninja)
        _ep_cmake_to_meson_buildtype(_libcamera_meson_bt)

        # Генеруємо meson cross-file для крос-компіляції
        _meson_generate_cross_file(_libcamera_cross_args)

        # libcamera-специфічний overlay.
        # -Wno-error=array-bounds — GCC 12 false-positive при ініціалізації
        #   std::vector<uint> через { 0 } (libcamera будується з -Werror).
        # strtoul/strtod → __isoc23_*@GLIBC_2.38 виправляється через:
        #   C файли:   c_std='c11' у meson-cross.ini
        #   C++ файли: preamble у MESON_CROSS_CXX_ARGS → __GLIBC_USE_C2X_STRTOL=0
        _meson_write_overlay(libcamera _libcamera_cross_args
            EXTRA_CXX -Wno-error=array-bounds)

        # libcamera pipeline handlers.
        # rpi/vc4 завжди включається: генерує control_ids_rpi.yaml, без якого
        # controls::rpi namespace не існує і rpicam-apps не компілюється.
        # rpi/pisp додається для RPi5 (BCM2712, PiSP ISP).
        # На x86_64 pipeline збирається (pure C++), але не запускається без хардвару.
        set(_libcamera_pipelines "rpi/vc4")
        set(_libcamera_ipas      "rpi/vc4")
        if(_EP_PLATFORM_RPI5)
            set(_libcamera_pipelines "rpi/vc4,rpi/pisp")
            set(_libcamera_ipas      "rpi/vc4,rpi/pisp")
        endif()

        # libcamera (RPi fork) встановлює згенеровані IPA-заголовки в
        # include/libcamera/libcamera/ через подвійний subdir у meson.build.
        # Після ninja install пересуваємо їх на рівень вгору і видаляємо
        # зайву директорію, щоб весь публічний API лежав у include/libcamera/.
        set(_libcamera_flatten_script
            "${CMAKE_BINARY_DIR}/_ep_cfg/libcamera-flatten-headers.cmake")
        file(WRITE "${_libcamera_flatten_script}" [[
set(_src "${SRC}")
set(_dst "${DST}")
if(IS_DIRECTORY "${_src}")
    file(GLOB _items LIST_DIRECTORIES true "${_src}/*")
    foreach(_item ${_items})
        file(COPY "${_item}" DESTINATION "${_dst}")
    endforeach()
    file(REMOVE_RECURSE "${_src}")
endif()
]])

        set(_libcamera_patch_pc_script
            "${CMAKE_BINARY_DIR}/_ep_cfg/libcamera-patch-pc.cmake")
        file(WRITE "${_libcamera_patch_pc_script}" [=[
set(_d "$")
foreach(_pc libcamera libcamera-base)
    set(_f "${PREFIX}/lib/pkgconfig/${_pc}.pc")
    if(EXISTS "${_f}")
        file(READ "${_f}" _c)
        string(REPLACE
            "Cflags: -I${_d}{includedir}/libcamera"
            "Cflags: -I${_d}{includedir}"
            _c "${_c}")
        file(WRITE "${_f}" "${_c}")
    endif()
endforeach()
]=])

        ExternalProject_Add(libcamera_ep
            GIT_REPOSITORY  "${LIBCAMERA_GIT_REPO}"
            GIT_TAG         "${LIBCAMERA_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libcamera"
            PATCH_COMMAND
            git apply "${CMAKE_CURRENT_LIST_DIR}/patches/libcamera-relocatable-paths.patch"
            CONFIGURE_COMMAND
            env
            PKG_CONFIG_PATH=${EXTERNAL_INSTALL_PREFIX}/lib/pkgconfig:${EXTERNAL_INSTALL_PREFIX}/share/pkgconfig
            ${_libcamera_meson} setup
            --reconfigure
            ${_libcamera_cross_args}
            --prefix=${EXTERNAL_INSTALL_PREFIX}
            --libdir=lib
            --buildtype=${_libcamera_meson_bt}
            -Dpipelines=${_libcamera_pipelines}
            -Dipas=${_libcamera_ipas}
            -Dlc-compliance=disabled
            -Dcam=enabled
            -Dqcam=disabled
            -Ddocumentation=disabled
            -Dtest=false
            <BINARY_DIR>
            <SOURCE_DIR>
            BUILD_COMMAND
            ${_libcamera_ninja} -C "<BINARY_DIR>" -j${_EP_NPROC}
            INSTALL_COMMAND
            ${_libcamera_ninja} -C "<BINARY_DIR>" install
            COMMAND ${CMAKE_COMMAND}
                "-DSRC=${EXTERNAL_INSTALL_PREFIX}/include/libcamera/libcamera"
                "-DDST=${EXTERNAL_INSTALL_PREFIX}/include/libcamera"
                -P "${_libcamera_flatten_script}"
            COMMAND ${CMAKE_COMMAND}
                "-DPREFIX=${EXTERNAL_INSTALL_PREFIX}"
                -P "${_libcamera_patch_pc_script}"
            # Зберігаємо приватний ключ підпису IPA у стабільне місце поза build-dir.
            # Build-dir видаляється при libcamera_ep-reset або cmake --clean.
            # Ключ потрібен для ре-підпису IPA .so після strip (RuntimeDeps.cmake).
            COMMAND ${CMAKE_COMMAND} -E make_directory
                "${EXTERNAL_INSTALL_PREFIX}/dependencies/libcamera/key/ipa"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "<BINARY_DIR>/src/ipa/ipa-priv-key.pem"
                "${EXTERNAL_INSTALL_PREFIX}/dependencies/libcamera/key/ipa/ipa-priv-key.pem"
            BUILD_BYPRODUCTS "${_libcamera_lib}" "${_libcamera_base_lib}"
            LOG_DOWNLOAD    ON
            LOG_CONFIGURE   ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

    ep_imported_library_from_ep(
        libcamera::libcamera libcamera_ep "${_libcamera_lib}" "${_libcamera_inc}")
    _libcamera_make_base_target(libcamera_ep)

    ep_track_cmake_file(libcamera_ep "${CMAKE_CURRENT_LIST_FILE}")
    ep_prestamp_git(libcamera_ep "${EP_SOURCES_DIR}/libcamera" "${LIBCAMERA_VERSION}")

    unset(_libcamera_meson)
    unset(_libcamera_ninja)
    unset(_libcamera_cross_args)
    unset(_libcamera_patch_pc_script)
    unset(_libcamera_pipelines)
    unset(_libcamera_ipas)
    unset(_libcamera_flatten_script)
    unset(_libcamera_patch_pc_script)
endif()

# ---------------------------------------------------------------------------
# Runtime ресурси libcamera (USE_SYSTEM=OFF: EP-збірка або вже в prefix)
#
# lib/libcamera/   — IPA .so модулі + .sign файли + ipa_*_proxy виконувані
# share/libcamera/ — конфіги pipeline (rpi/vc4/, rpi/pisp/) та IPA
# etc/libcamera/   — системні IPA конфіги (tuning файли тощо)
#
# NO_STRIP: IPA .so мають SHA256-підпис (ipa_*.so.sign). Strip без ре-підпису
#   інвалідує підпис → libcamera відмовляється завантажувати плагін.
# SIGN_KEY: при DO_STRIP=ON RuntimeDeps автоматично виконає strip + resign.
#   Ключ копіюється з build-dir у dependencies/ при кожному ninja install.
# ---------------------------------------------------------------------------
if(NOT USE_SYSTEM_LIBCAMERA AND TARGET libcamera::libcamera)
    ep_register_runtime_dirs(libcamera::libcamera
        BASE_DIR "${EXTERNAL_INSTALL_PREFIX}"
        DIRS
            lib/libcamera
            share/libcamera
            etc/libcamera
        NO_STRIP
        SIGN_KEY
            "${EXTERNAL_INSTALL_PREFIX}/dependencies/libcamera/key/ipa/ipa-priv-key.pem"
    )
endif()

endif()

unset(_libcamera_lib)
unset(_libcamera_base_lib)
unset(_libcamera_inc)
