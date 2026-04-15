# cmake/external/LibJpeg.cmake
#
# Збирає або знаходить libjpeg (використовує libjpeg-turbo — швидший завдяки
# SIMD-оптимізаціям, повністю сумісний з libjpeg API).
#
# Provides imported target:
#   JPEG::JPEG  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_LIBJPEG  — ON: find_package в системі/sysroot
#                         OFF (за замовченням): зібрати через ExternalProject
#
# Кеш-змінні:
#   LIBJPEG_VERSION    — версія libjpeg-turbo (git тег)
#   LIBJPEG_GIT_REPO   — URL git репозиторію

option(USE_SYSTEM_LIBJPEG
    "Використовувати системний libjpeg (find_package) замість збірки libjpeg-turbo"
    OFF)

set(LIBJPEG_VERSION  "3.0.3"
    CACHE STRING "Версія libjpeg-turbo для збірки з джерел")

set(LIBJPEG_GIT_REPO
    "https://github.com/libjpeg-turbo/libjpeg-turbo.git"
    CACHE STRING "Git репозиторій libjpeg-turbo")

# ---------------------------------------------------------------------------

set(_jpeg_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libjpeg.so")
set(_jpeg_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_LIBJPEG)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(JPEG REQUIRED)
    message(STATUS "[LibJpeg] Системна бібліотека: ${JPEG_LIBRARIES}")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(JPEG QUIET HINTS "${EXTERNAL_INSTALL_PREFIX}" NO_DEFAULT_PATH)
    if(JPEG_FOUND)
        message(STATUS "[LibJpeg] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[LibJpeg] Буде зібрано з джерел (libjpeg-turbo ${LIBJPEG_VERSION})")

        ep_cmake_args(_jpeg_cmake_args
            -DENABLE_SHARED=ON
            -DENABLE_STATIC=OFF
            # WITH_JPEG8=ON: ABI-сумісність з libjpeg 8 (потрібно для OpenCV)
            -DWITH_JPEG8=ON
            # TurboJPEG C API — окремий від libjpeg, тут не потрібен
            -DWITH_TURBOJPEG=OFF
            -DWITH_JAVA=OFF
            -DWITH_MAN=OFF
        )

        ExternalProject_Add(libjpeg_ep
            GIT_REPOSITORY  "${LIBJPEG_GIT_REPO}"
            GIT_TAG         "${LIBJPEG_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libjpeg"
            CMAKE_ARGS      ${_jpeg_cmake_args}
            BUILD_BYPRODUCTS "${_jpeg_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(JPEG::JPEG libjpeg_ep "${_jpeg_lib}" "${_jpeg_inc}")
    endif()
endif()

unset(_jpeg_lib)
unset(_jpeg_inc)
