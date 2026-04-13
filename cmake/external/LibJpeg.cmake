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
#   LIBJPEG_VERSION    — версія libjpeg-turbo для збірки
#   LIBJPEG_URL        — URL архіву
#   LIBJPEG_URL_HASH   — SHA256 хеш (порожньо = не перевіряти)

option(USE_SYSTEM_LIBJPEG
    "Використовувати системний libjpeg (find_package) замість збірки libjpeg-turbo"
    OFF)

set(LIBJPEG_VERSION  "3.0.3"
    CACHE STRING "Версія libjpeg-turbo для збірки з джерел")

set(LIBJPEG_URL
    "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/${LIBJPEG_VERSION}/libjpeg-turbo-${LIBJPEG_VERSION}.tar.gz"
    CACHE STRING "URL архіву libjpeg-turbo")

set(LIBJPEG_URL_HASH ""
    CACHE STRING "SHA256 хеш архіву libjpeg-turbo (порожньо = не перевіряти)")

# ---------------------------------------------------------------------------

set(_jpeg_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libjpeg.so")
set(_jpeg_inc "${EXTERNAL_INSTALL_PREFIX}/include")
set(_jpeg_hdr "${EXTERNAL_INSTALL_PREFIX}/include/jpeglib.h")

if(USE_SYSTEM_LIBJPEG)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(JPEG REQUIRED)
    message(STATUS "[LibJpeg] Системна бібліотека: ${JPEG_LIBRARIES}")

else()
    # ── Збірка через ExternalProject ────────────────────────────────────────
    if(EXISTS "${_jpeg_lib}" AND EXISTS "${_jpeg_hdr}")
        message(STATUS "[LibJpeg] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")
        ep_imported_library(JPEG::JPEG "${_jpeg_lib}" "${_jpeg_inc}")

    else()
        message(STATUS "[LibJpeg] Буде зібрано з джерел (libjpeg-turbo ${LIBJPEG_VERSION})")

        set(_jpeg_hash_arg "")
        if(LIBJPEG_URL_HASH)
            set(_jpeg_hash_arg URL_HASH "SHA256=${LIBJPEG_URL_HASH}")
        endif()

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
            URL             "${LIBJPEG_URL}"
            ${_jpeg_hash_arg}
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
unset(_jpeg_hdr)
