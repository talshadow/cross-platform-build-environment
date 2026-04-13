# cmake/external/LibTiff.cmake
#
# Збирає або знаходить libtiff.
# Якщо JPEG::JPEG та PNG::PNG вже оголошені — автоматично прив'язується до них.
#
# Provides imported target:
#   TIFF::TIFF  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_LIBTIFF  — ON: find_package в системі/sysroot
#                         OFF (за замовченням): зібрати через ExternalProject
#
# Кеш-змінні:
#   LIBTIFF_VERSION    — версія для збірки
#   LIBTIFF_URL        — URL архіву
#   LIBTIFF_URL_HASH   — SHA256 хеш (порожньо = не перевіряти)

option(USE_SYSTEM_LIBTIFF
    "Використовувати системний libtiff (find_package) замість збірки з джерел"
    OFF)

set(LIBTIFF_VERSION  "4.6.0"
    CACHE STRING "Версія libtiff для збірки з джерел")

set(LIBTIFF_URL
    "https://download.osgeo.org/libtiff/tiff-${LIBTIFF_VERSION}.tar.gz"
    CACHE STRING "URL архіву libtiff")

set(LIBTIFF_URL_HASH ""
    CACHE STRING "SHA256 хеш архіву libtiff (порожньо = не перевіряти)")

# ---------------------------------------------------------------------------

set(_tiff_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libtiff.so")
set(_tiff_inc "${EXTERNAL_INSTALL_PREFIX}/include")
set(_tiff_hdr "${EXTERNAL_INSTALL_PREFIX}/include/tiff.h")

if(USE_SYSTEM_LIBTIFF)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(TIFF REQUIRED)
    message(STATUS "[LibTiff] Системна бібліотека: ${TIFF_LIBRARIES}")

else()
    # ── Збірка через ExternalProject ────────────────────────────────────────
    if(EXISTS "${_tiff_lib}" AND EXISTS "${_tiff_hdr}")
        message(STATUS "[LibTiff] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")
        ep_imported_library(TIFF::TIFF "${_tiff_lib}" "${_tiff_inc}")

    else()
        message(STATUS "[LibTiff] Буде зібрано з джерел (версія ${LIBTIFF_VERSION})")

        set(_tiff_hash_arg "")
        if(LIBTIFF_URL_HASH)
            set(_tiff_hash_arg URL_HASH "SHA256=${LIBTIFF_URL_HASH}")
        endif()

        # Формуємо додаткові аргументи — шляхи до вже зібраних deps
        set(_tiff_dep_args "")

        if(TARGET JPEG::JPEG)
            get_target_property(_jpeg_loc JPEG::JPEG IMPORTED_LOCATION)
            # NOTFOUND — якщо target є INTERFACE (напр. системний через find_package)
            if(_jpeg_loc AND NOT _jpeg_loc MATCHES "NOTFOUND")
                list(APPEND _tiff_dep_args
                    "-DJPEG_LIBRARY=${_jpeg_loc}"
                    "-DJPEG_INCLUDE_DIR=${EXTERNAL_INSTALL_PREFIX}/include"
                )
            endif()
        endif()

        if(TARGET PNG::PNG)
            get_target_property(_png_loc PNG::PNG IMPORTED_LOCATION)
            if(_png_loc AND NOT _png_loc MATCHES "NOTFOUND")
                list(APPEND _tiff_dep_args
                    "-DPNG_LIBRARY=${_png_loc}"
                    "-DPNG_PNG_INCLUDE_DIR=${EXTERNAL_INSTALL_PREFIX}/include"
                )
            endif()
        endif()

        ep_cmake_args(_tiff_cmake_args
            -Dtiff-docs=OFF
            -Dtiff-tests=OFF
            -Dtiff-tools=OFF
            -Dtiff-contrib=OFF
            ${_tiff_dep_args}
        )

        # Залежності від EP що будуються паралельно (якщо є)
        # _ep_collect_deps повертає тільки імена цілей (без "DEPENDS")
        _ep_collect_deps(_tiff_ep_targets libjpeg_ep libpng_ep)

        ExternalProject_Add(libtiff_ep
            URL             "${LIBTIFF_URL}"
            ${_tiff_hash_arg}
            CMAKE_ARGS      ${_tiff_cmake_args}
            BUILD_BYPRODUCTS "${_tiff_lib}"
            DEPENDS          ${_tiff_ep_targets}
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(TIFF::TIFF libtiff_ep "${_tiff_lib}" "${_tiff_inc}")
    endif()
endif()

unset(_tiff_lib)
unset(_tiff_inc)
unset(_tiff_hdr)
