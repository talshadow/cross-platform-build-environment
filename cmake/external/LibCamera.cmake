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
        # libcamera не має LibcameraConfig.cmake — перевіряємо .so напряму
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

        # libcamera-специфічний overlay cross-файл.
        # ВАЖЛИВО: meson використовує останній --cross-file для [built-in options],
        # тому overlay МУСИТЬ містити ВСІ cpp_args (не тільки libcamera-специфічні).
        # MESON_CROSS_C_ARGS/MESON_CROSS_LINK_ARGS виставляються _meson_generate_cross_file.
        #
        # Додатковий прапор: -Wno-error=array-bounds
        # Пригнічує GCC 12 false-positive (hdr.cpp:119):
        # libcamera будується з -Werror, і GCC 12 помилково генерує цей варнінг
        # при ініціалізації std::vector<uint> через { 0 }.
        set(_libcamera_overlay_file "${CMAKE_BINARY_DIR}/_ep_cfg/meson-libcamera-overlay.ini")
        if(MESON_CROSS_C_ARGS)
            # Крос-компіляція: повний набір cpp_args + libcamera-специфічний прапор
            set(_overlay_cpp_args "${MESON_CROSS_C_ARGS}, '-Wno-error=array-bounds'")
            set(_overlay_link_args "${MESON_CROSS_LINK_ARGS}")
            file(WRITE "${_libcamera_overlay_file}"
                "[built-in options]
                cpp_args = [${_overlay_cpp_args}]
                c_args = [${MESON_CROSS_C_ARGS}]
                c_link_args = [${_overlay_link_args}]
                cpp_link_args = [${_overlay_link_args}]
                ")
            unset(_overlay_cpp_args)
            unset(_overlay_link_args)
        else()
            # Нативна збірка: libcamera-специфічний прапор + include нашого prefix.
            # Workaround: apps/common/meson.build додає event_loop.cpp коли libevent
            # знайдено, але не оголошує libevent як dep apps_lib — тому -I не
            # потрапляє в команду компіляції автоматично.
            file(WRITE "${_libcamera_overlay_file}"
                "[built-in options]
                cpp_args = ['-Wno-error=array-bounds', '-I${EXTERNAL_INSTALL_PREFIX}/include']
                ")
        endif()
        # При нативній збірці використовуємо --native-file щоб не активувати
        # cross-compilation mode у meson (--cross-file завжди його вмикає).
        if(CMAKE_CROSSCOMPILING)
            list(APPEND _libcamera_cross_args "--cross-file"   "${_libcamera_overlay_file}")
        else()
            list(APPEND _libcamera_cross_args "--native-file"  "${_libcamera_overlay_file}")
        endif()

        # libcamera pipeline handlers.
        # Завжди включаємо rpi/vc4 — потрібен для генерації control_ids_rpi.yaml,
        # без якого controls::rpi namespace не існує і rpicam-apps не компілюється.
        # На x86_64 pipeline збирається (pure C++), але не запускається без хардвару.
        set(_libcamera_pipelines "rpi/vc4")

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

        ExternalProject_Add(libcamera_ep
            GIT_REPOSITORY  "${LIBCAMERA_GIT_REPO}"
            GIT_TAG         "${LIBCAMERA_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libcamera"
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
            -Dipas=rpi/vc4
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
    unset(_libcamera_overlay_file)
    unset(_libcamera_pipelines)
    unset(_libcamera_flatten_script)
endif()
endif()

unset(_libcamera_lib)
unset(_libcamera_base_lib)
unset(_libcamera_inc)
