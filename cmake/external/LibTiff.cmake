# cmake/external/LibTiff.cmake
#
# Збирає або знаходить libtiff.
# Якщо JPEG::JPEG та PNG::PNG вже оголошені — автоматично прив'язується до них.
#
# Provides imported target:
#   TIFF::TIFF  — SHARED IMPORTED
#
# Увімкнені кодеки (як Ubuntu libtiff6):
#   zlib        — завжди (вбудований у libtiff)
#   lzma/xz     — liblzma (з sysroot або системи); auto-detect
#   zstd        — libzstd (з sysroot або системи); auto-detect
#   webp        — libwebp (з sysroot або системи); auto-detect
#   lerc        — liblerc (з sysroot або системи); auto-detect
#   libdeflate  — libdeflate (з sysroot або системи); auto-detect
#
# Всі кодеки встановлені в ON (libtiff semantics: "спробувати знайти, попередити
# якщо не знайдено, не падати"). Якщо бібліотека відсутня в sysroot/системі —
# кодек буде тихо відключений з WARNING у лозі збірки.
#
# Опції:
#   USE_SYSTEM_LIBTIFF  — ON: find_package в системі/sysroot
#                         OFF (за замовченням): зібрати через ExternalProject
#
# Кеш-змінні:
#   LIBTIFF_VERSION    — версія (git тег)
#   LIBTIFF_GIT_REPO   — URL git репозиторію

option(USE_SYSTEM_LIBTIFF
    "Використовувати системний libtiff (find_package) замість збірки з джерел"
    ON)

set(LIBTIFF_VERSION  "4.6.0"
    CACHE STRING "Версія libtiff для збірки з джерел")

set(LIBTIFF_GIT_REPO
    "https://gitlab.com/libtiff/libtiff.git"
    CACHE STRING "Git репозиторій libtiff (GitLab — офіційний upstream)")

# ---------------------------------------------------------------------------

set(_tiff_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libtiff.so")
set(_tiff_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_LIBTIFF)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(TIFF REQUIRED)
    message(STATUS "[LibTiff] Системна бібліотека: ${TIFF_LIBRARIES}")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(TIFF QUIET HINTS "${EXTERNAL_INSTALL_PREFIX}" NO_DEFAULT_PATH)
    if(TIFF_FOUND)
        message(STATUS "[LibTiff] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_tiff_lib}")
        ep_imported_library(TIFF::TIFF "${_tiff_lib}" "${_tiff_inc}")
        message(STATUS "[LibTiff] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[LibTiff] Буде зібрано з джерел (версія ${LIBTIFF_VERSION})")

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
            # Кодеки стиснення — як Ubuntu libtiff6.
            # Семантика libtiff: ON = "знайти, якщо є; попередити і пропустити якщо нема".
            # Бібліотеки шукаються в EXTERNAL_INSTALL_PREFIX та sysroot (крос)
            # або в системі (нативна збірка) — через ep_find_scope з ep_cmake_args.
            -Dzstd=ON           # libzstd  — сучасне стиснення (TIFF 4.x+)
            -Dlzma=ON           # liblzma  — XZ/LZMA стиснення
            -Dwebp=ON           # libwebp  — WebP у TIFF (рідко, але Ubuntu має)
            -Dlerc=ON           # liblerc  — LERC стиснення (TIFF 4.4+)
            -Dlibdeflate=ON     # libdeflate — швидший deflate (Ubuntu 22.04+)
            # jbig: Ubuntu відключає (-Djbig=FALSE), залишаємо OFF
            -Djbig=OFF
            ${_tiff_dep_args}
        )

        ExternalProject_Add(libtiff_ep
            GIT_REPOSITORY  "${LIBTIFF_GIT_REPO}"
            GIT_TAG         "v${LIBTIFF_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libtiff"
            CMAKE_ARGS      ${_tiff_cmake_args}
            BUILD_BYPRODUCTS "${_tiff_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(TIFF::TIFF libtiff_ep "${_tiff_lib}" "${_tiff_inc}")
        ep_track_cmake_file(libtiff_ep "${CMAKE_CURRENT_LIST_FILE}")
    endif()
endif()

unset(_tiff_lib)
unset(_tiff_inc)
