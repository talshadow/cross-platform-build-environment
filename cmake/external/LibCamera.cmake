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

set(LIBCAMERA_VERSION "v0.3.2"
    CACHE STRING "Версія libcamera для збірки з джерел")

set(LIBCAMERA_GIT_REPO
    "https://github.com/raspberrypi/libcamera.git"
    CACHE STRING "Git репозиторій libcamera (Raspberry Pi форк)")

# ---------------------------------------------------------------------------

set(_libcamera_lib  "${EXTERNAL_INSTALL_PREFIX}/lib/libcamera.so")
set(_libcamera_inc  "${EXTERNAL_INSTALL_PREFIX}/include")

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

        # libcamera pipeline handlers — для RPi включаємо rpi/vc4
        if(CMAKE_CROSSCOMPILING)
            set(_libcamera_pipelines "rpi/vc4")
        else()
            set(_libcamera_pipelines "auto")
        endif()

        # cam потребує libevent — передаємо через PKG_CONFIG_PATH
        _ep_collect_deps(_libcamera_ep_deps libevent_ep)

        ExternalProject_Add(libcamera_ep
            GIT_REPOSITORY  "${LIBCAMERA_GIT_REPO}"
            GIT_TAG         "${LIBCAMERA_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libcamera"
            DEPENDS         ${_libcamera_ep_deps}
            CONFIGURE_COMMAND
                env
                    PKG_CONFIG_PATH=${EXTERNAL_INSTALL_PREFIX}/lib/pkgconfig:${EXTERNAL_INSTALL_PREFIX}/share/pkgconfig
                ${_libcamera_meson} setup
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
            BUILD_BYPRODUCTS "${_libcamera_lib}"
            LOG_DOWNLOAD    ON
            LOG_CONFIGURE   ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(
            libcamera::libcamera libcamera_ep "${_libcamera_lib}" "${_libcamera_inc}")

        unset(_libcamera_meson)
        unset(_libcamera_ninja)
        unset(_libcamera_cross_args)
        unset(_libcamera_pipelines)
        unset(_libcamera_ep_deps)
    endif()
endif()

unset(_libcamera_lib)
unset(_libcamera_inc)
