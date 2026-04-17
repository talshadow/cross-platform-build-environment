# cmake/external/RpiCamApps.cmake
#
# rpicam-apps — фреймворк та утиліти Raspberry Pi для роботи з камерами
# на основі libcamera (rpicam-still, rpicam-vid, rpicam-raw, тощо).
# https://github.com/raspberrypi/rpicam-apps
#
# Provides imported target:
#   rpicam_apps::camera_app  — SHARED IMPORTED (rpicam_app.so)
#
# Залежності:
#   - libcamera::libcamera (libcamera_ep)
#   - Boost::headers / boost_ep (опційно, для деяких post-processing stages)
#
# Примітки:
#   - Meson-based збірка. Потребує meson та ninja в PATH хоста.
#   - USE_SYSTEM_RPICAMAPPS=ON (за замовч.) — взяти з sysroot/системи.
#     Зазвичай постачається разом з Raspberry Pi OS.
#   - USE_SYSTEM_RPICAMAPPS=OFF — зібрати з джерел.
#
# Опції:
#   USE_SYSTEM_RPICAMAPPS  — ON (за замовч.): find_package / pkg-config
#                            OFF: зібрати через Meson ExternalProject
#
# Кеш-змінні:
#   RPICAMAPPS_VERSION, RPICAMAPPS_GIT_REPO

option(USE_SYSTEM_RPICAMAPPS
    "Використовувати системну rpicam-apps замість збірки з джерел (рекомендовано)"
    OFF)

set(RPICAMAPPS_VERSION "v1.9.1"
    CACHE STRING "Версія rpicam-apps для збірки з джерел")

set(RPICAMAPPS_GIT_REPO
    "https://github.com/raspberrypi/rpicam-apps.git"
    CACHE STRING "Git репозиторій rpicam-apps")

# ---------------------------------------------------------------------------

set(_rpicam_lib "${EXTERNAL_INSTALL_PREFIX}/lib/librpicam_app.so")
set(_rpicam_inc "${EXTERNAL_INSTALL_PREFIX}/include/rpicam-apps")

if(USE_SYSTEM_RPICAMAPPS)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(rpicam_app QUIET)
    if(rpicam_app_FOUND)
        message(STATUS "[RpiCamApps] Системна: rpicam_apps::camera_app")
    else()
        find_package(PkgConfig QUIET)
        if(PkgConfig_FOUND)
            pkg_check_modules(RPICAM_APP IMPORTED_TARGET rpicam-apps)
            if(RPICAM_APP_FOUND)
                if(NOT TARGET rpicam_apps::camera_app)
                    add_library(rpicam_apps::camera_app INTERFACE IMPORTED GLOBAL)
                    set_property(TARGET rpicam_apps::camera_app
                        APPEND PROPERTY INTERFACE_LINK_LIBRARIES PkgConfig::RPICAM_APP)
                endif()
                message(STATUS "[RpiCamApps] Системна (pkg-config): ${RPICAM_APP_LIBRARIES}")
            else()
                message(WARNING "[RpiCamApps] USE_SYSTEM_RPICAMAPPS=ON але rpicam-apps не знайдено. "
                    "Встановіть rpicam-apps (доступний у Raspberry Pi OS) або передайте "
                    "USE_SYSTEM_RPICAMAPPS=OFF для збірки з джерел.")
            endif()
        else()
            message(WARNING "[RpiCamApps] USE_SYSTEM_RPICAMAPPS=ON але pkg-config недоступний. "
                "Встановіть rpicam-apps вручну.")
        endif()
    endif()

else()
    # ── Алгоритм: find_package → ExternalProject_Add (Meson) ───────────────
    find_package(rpicam_app QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(rpicam_app_FOUND)
        message(STATUS "[RpiCamApps] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_rpicam_lib}")
        ep_imported_library(rpicam_apps::camera_app "${_rpicam_lib}" "${_rpicam_inc}")
        message(STATUS "[RpiCamApps] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[RpiCamApps] Буде зібрано з джерел (${RPICAMAPPS_VERSION}) через Meson")

        _ep_require_meson()
        find_program(_rpicam_meson meson)
        find_program(_rpicam_ninja ninja)
        _ep_cmake_to_meson_buildtype(_rpicam_meson_bt)

        # Генеруємо meson cross-file для крос-компіляції
        _meson_generate_cross_file(_rpicam_cross_args)

        ExternalProject_Add(rpicamapps_ep
            GIT_REPOSITORY  "${RPICAMAPPS_GIT_REPO}"
            GIT_TAG         "${RPICAMAPPS_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/rpicamapps"
            CONFIGURE_COMMAND
                env
                    PKG_CONFIG_PATH=${EXTERNAL_INSTALL_PREFIX}/lib/pkgconfig:${EXTERNAL_INSTALL_PREFIX}/share/pkgconfig
                    BOOST_ROOT=${EXTERNAL_INSTALL_PREFIX}
                    BOOST_INCLUDEDIR=${EXTERNAL_INSTALL_PREFIX}/include
                    BOOST_LIBRARYDIR=${EXTERNAL_INSTALL_PREFIX}/lib
                ${_rpicam_meson} setup
                    --reconfigure
                    ${_rpicam_cross_args}
                    --prefix=${EXTERNAL_INSTALL_PREFIX}
                    --libdir=lib
                    --buildtype=${_rpicam_meson_bt}
                    -Denable_libav=disabled
                    -Denable_drm=disabled
                    -Denable_egl=disabled
                    -Denable_qt=disabled
                    -Denable_opencv=enabled
                    -Denable_tflite=disabled
                    <BINARY_DIR>
                    <SOURCE_DIR>
            BUILD_COMMAND
                ${_rpicam_ninja} -C "<BINARY_DIR>" -j${_EP_NPROC}
            INSTALL_COMMAND
                ${_rpicam_ninja} -C "<BINARY_DIR>" install
            BUILD_BYPRODUCTS "${_rpicam_lib}"
            LOG_DOWNLOAD    ON
            LOG_CONFIGURE   ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(
            rpicam_apps::camera_app rpicamapps_ep "${_rpicam_lib}" "${_rpicam_inc}")

        ep_prestamp_git(rpicamapps_ep "${EP_SOURCES_DIR}/rpicamapps" "${RPICAMAPPS_VERSION}")

        unset(_rpicam_meson)
        unset(_rpicam_ninja)
        unset(_rpicam_cross_args)
    endif()
endif()

unset(_rpicam_lib)
unset(_rpicam_inc)
