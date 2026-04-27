# cmake/external/OpenCV.cmake
#
# Збирає або знаходить OpenCV разом з opencv_contrib.
# opencv_contrib завантажується як окремий EP (тільки unpack, без збірки).
#
# При збірці автоматично використовує вже підключені залежності:
#   JPEG::JPEG, PNG::PNG, TIFF::TIFF, OpenSSL::SSL
#
# Provides imported targets (після першої успішної збірки — через find_package):
#   Core: opencv_core, opencv_imgproc, opencv_imgcodecs, opencv_highgui,
#         opencv_videoio, opencv_video, opencv_features2d, opencv_calib3d,
#         opencv_objdetect, opencv_dnn, opencv_ml, opencv_flann, opencv_photo
#   Contrib: opencv_aruco, opencv_bgsegm, opencv_bioinspired, opencv_ccalib,
#            opencv_datasets, opencv_dnn_objdetect, opencv_dnn_superres, opencv_dpm,
#            opencv_face, opencv_freetype, opencv_fuzzy, opencv_hdf, opencv_hfs,
#            opencv_img_hash, opencv_intensity_transform, opencv_line_descriptor,
#            opencv_mcc, opencv_optflow, opencv_ovis, opencv_phase_unwrapping,
#            opencv_plot, opencv_quality, opencv_rapid, opencv_reg, opencv_rgbd,
#            opencv_saliency, opencv_sfm, opencv_shape, opencv_stereo,
#            opencv_structured_light, opencv_superres, opencv_surface_matching,
#            opencv_text, opencv_tracking, opencv_videostab, opencv_viz,
#            opencv_wechat_qrcode, opencv_xfeatures2d, opencv_ximgproc,
#            opencv_xobjdetect, opencv_xphoto
#   Всі таргети доступні як OpenCV::<module_name>
#
# При першій збірці (бібліотека ще не встановлена) — placeholder targets
# з майбутніми шляхами. Після `cmake --build` повторна конфігурація
# автоматично перейде на реальні targets через find_package.
#
# Опції:
#   USE_SYSTEM_OPENCV      — ON: find_package в системі/sysroot
#                            OFF (за замовченням): зібрати через ExternalProject
#   OPENCV_ENABLE_CONTRIB  — ON (за замовченням): включати opencv_contrib модулі
#   OPENCV_WITH_FFMPEG     — ON (за замовченням): увімкнути підтримку FFmpeg
#                            Потребує libavcodec/avformat/avutil/swscale-dev в sysroot.
#                            При крос-збірці: pkg-config повинен бачити ffmpeg з sysroot.
#   OPENCV_WITH_OPENCL     — ON (за замовченням): увімкнути підтримку OpenCL
#                            Потребує OpenCL ICD loader (libOpenCL.so) і заголовків
#                            (opencl-headers) в sysroot або на хості.
#   OPENCV_WITH_V4L2       — ON (за замовченням): увімкнути підтримку V4L2 (kernel headers)
#                            Потребує linux/videodev2.h в sysroot.
#   OPENCV_WITH_LIBV4L     — ON (за замовченням): використовувати libv4l2 userspace wrapper
#                            Потребує libv4l-dev в sysroot; якщо відсутній — OpenCV ігнорує.
#   OPENCV_ENABLE_NONFREE  — ON (за замовченням): non-free алгоритми (SIFT, SURF тощо)
#                            Увага: патентні обмеження в деяких юрисдикціях.
#
# Кеш-змінні:
#   OPENCV_VERSION          — версія (git тег або архів)
#   OPENCV_GIT_REPO         — URL git репозиторію OpenCV (тільки при OPENCV_USE_GIT=ON)
#   OPENCV_CONTRIB_GIT_REPO — URL git репозиторію opencv_contrib (тільки при OPENCV_USE_GIT=ON)

option(USE_SYSTEM_OPENCV
    "Використовувати системний OpenCV (find_package) замість збірки з джерел"
    OFF)

option(OPENCV_ENABLE_CONTRIB
    "Включати opencv_contrib модулі при збірці"
    ON)

option(OPENCV_WITH_FFMPEG
    "Збирати OpenCV з підтримкою FFmpeg (потребує ffmpeg dev-libs в sysroot/системі)"
    ON)

option(OPENCV_WITH_OPENCL
    "Збирати OpenCV з підтримкою OpenCL (потребує OpenCL ICD loader в sysroot/системі)"
    ON)

option(OPENCV_WITH_V4L2
    "Збирати OpenCV з підтримкою V4L2 (потребує linux/videodev2.h в sysroot)"
    ON)

option(OPENCV_WITH_LIBV4L
    "Використовувати libv4l2 userspace wrapper (потребує libv4l-dev в sysroot; auto-detected)"
    ON)

option(OPENCV_ENABLE_NONFREE
    "Увімкнути non-free алгоритми OpenCV (SIFT, SURF тощо; обмеження патентів)"
    ON)

option(OPENCV_USE_GIT
    "Завантажувати OpenCV через git clone (OFF = архів з GitHub Releases)"
    OFF)

set(OPENCV_VERSION  "4.13.0"
    CACHE STRING "Версія OpenCV для збірки з джерел")

set(OPENCV_GIT_REPO
    "https://github.com/opencv/opencv.git"
    CACHE STRING "Git репозиторій OpenCV (використовується тільки при OPENCV_USE_GIT=ON)")

set(OPENCV_CONTRIB_GIT_REPO
    "https://github.com/opencv/opencv_contrib.git"
    CACHE STRING "Git репозиторій opencv_contrib (використовується тільки при OPENCV_USE_GIT=ON)")

# ---------------------------------------------------------------------------

set(_ocv_prefix  "${EXTERNAL_INSTALL_PREFIX}")
set(_ocv_lib_dir "${_ocv_prefix}/lib")
set(_ocv_inc_dir "${_ocv_prefix}/include/opencv4")
set(_ocv_core    "${_ocv_lib_dir}/libopencv_core.so")

# Список модулів для placeholder targets (використовується якщо бібліотека ще не зібрана)
set(_ocv_modules
    # core modules
    opencv_core
    opencv_imgproc
    opencv_imgcodecs
    opencv_highgui
    opencv_videoio
    opencv_video
    opencv_features2d
    opencv_calib3d
    opencv_objdetect
    opencv_dnn
    opencv_ml
    opencv_flann
    opencv_photo
    # contrib modules
    opencv_aruco
    opencv_bgsegm
    opencv_bioinspired
    opencv_ccalib
    opencv_datasets
    opencv_dnn_objdetect
    opencv_dnn_superres
    opencv_dpm
    opencv_face
    opencv_freetype
    opencv_fuzzy
    opencv_hdf
    opencv_hfs
    opencv_img_hash
    opencv_intensity_transform
    opencv_line_descriptor
    opencv_mcc
    opencv_optflow
    opencv_ovis
    opencv_phase_unwrapping
    opencv_plot
    opencv_quality
    opencv_rapid
    opencv_reg
    opencv_rgbd
    opencv_saliency
    opencv_sfm
    opencv_shape
    opencv_stereo
    opencv_structured_light
    opencv_superres
    opencv_surface_matching
    opencv_text
    opencv_tracking
    opencv_videostab
    opencv_viz
    opencv_wechat_qrcode
    opencv_xfeatures2d
    opencv_ximgproc
    opencv_xobjdetect
    opencv_xphoto
)

# Хелпер: створює OpenCV:: IMPORTED targets для вже встановленого або EP OpenCV
macro(_ocv_make_imported_targets ep_name_or_empty)
    # CMake 3.28+ валідує INTERFACE_INCLUDE_DIRECTORIES при конфігурації.
    # Для placeholder-targets (EP ще не зібрано) директорії можуть не існувати.
    file(MAKE_DIRECTORY "${_ocv_inc_dir}" "${_ocv_prefix}/include")
    foreach(_mod ${_ocv_modules})
        if(NOT TARGET OpenCV::${_mod})
            set(_mod_lib "${_ocv_lib_dir}/lib${_mod}.so")
            add_library(OpenCV::${_mod} SHARED IMPORTED GLOBAL)
            set_target_properties(OpenCV::${_mod} PROPERTIES
                IMPORTED_LOCATION             "${_mod_lib}"
                INTERFACE_INCLUDE_DIRECTORIES "${_ocv_inc_dir};${_ocv_prefix}/include"
            )
            if(ep_name_or_empty AND TARGET ${ep_name_or_empty})
                _ep_make_sync_target(${ep_name_or_empty})
                set_property(TARGET OpenCV::${_mod} APPEND PROPERTY
                    INTERFACE_LINK_LIBRARIES _ep_sync_${ep_name_or_empty})
            endif()
        endif()
    endforeach()
endmacro()

# Хелпер: OpenCV:: ALIAS для targets, які створює сам OpenCV CMake config (opencv_core тощо)
macro(_ocv_make_namespace_aliases)
    foreach(_mod ${_ocv_modules})
        if(TARGET ${_mod} AND NOT TARGET OpenCV::${_mod})
            add_library(OpenCV::${_mod} ALIAS ${_mod})
        endif()
    endforeach()
endmacro()

# ---------------------------------------------------------------------------

if(USE_SYSTEM_OPENCV)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(OpenCV REQUIRED)
    _ocv_make_namespace_aliases()
    message(STATUS "[OpenCV] Системна бібліотека версії ${OpenCV_VERSION}")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(OpenCV QUIET HINTS "${_ocv_prefix}" NO_DEFAULT_PATH)
    if(OpenCV_FOUND)
        _ocv_make_namespace_aliases()
        message(STATUS "[OpenCV] Знайдено готову бібліотеку у ${_ocv_prefix} (${OpenCV_VERSION})")

    elseif(EXISTS "${_ocv_core}")
        _ocv_make_imported_targets("")
        message(STATUS "[OpenCV] Знайдено .so у ${_ocv_prefix}")

    else()
        message(STATUS "[OpenCV] Буде зібрано з джерел (версія ${OPENCV_VERSION})")

        # ── opencv_contrib: тільки clone, збірка відбувається у opencv_ep ─
        set(_contrib_src "${EP_SOURCES_DIR}/opencv_contrib")

        if(OPENCV_ENABLE_CONTRIB)
            if(OPENCV_USE_GIT)
                set(_ocv_contrib_download_args
                    GIT_REPOSITORY   "${OPENCV_CONTRIB_GIT_REPO}"
                    GIT_TAG          "${OPENCV_VERSION}"
                    GIT_SHALLOW      ON
                )
            else()
                set(_ocv_contrib_download_args
                    URL "https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.tar.gz"
                    DOWNLOAD_EXTRACT_TIMESTAMP ON
                )
            endif()

            ExternalProject_Add(opencv_contrib_ep
                ${_ocv_contrib_download_args}
                SOURCE_DIR       "${_contrib_src}"
                CONFIGURE_COMMAND ""
                BUILD_COMMAND     ""
                INSTALL_COMMAND   ""
                LOG_DOWNLOAD      ON
            )
            set(_ocv_contrib_arg
                "-DOPENCV_EXTRA_MODULES_PATH=${_contrib_src}/modules")
        else()
            set(_ocv_contrib_arg "")
        endif()

        # ── Збираємо аргументи залежних бібліотек ─────────────────────────
        set(_ocv_dep_args
            # Вимикаємо пошук системних бібліотек якщо не вказано явно
            -DWITH_JASPER=OFF
            -DWITH_WEBP=OFF
            -DWITH_OPENJPEG=OFF
        )

        if(TARGET JPEG::JPEG)
            get_target_property(_jpeg_loc JPEG::JPEG IMPORTED_LOCATION)
            if(_jpeg_loc AND NOT _jpeg_loc MATCHES "NOTFOUND")
                list(APPEND _ocv_dep_args
                    -DWITH_JPEG=ON
                    "-DJPEG_LIBRARY=${_jpeg_loc}"
                    "-DJPEG_INCLUDE_DIR=${EXTERNAL_INSTALL_PREFIX}/include"
                )
            endif()
        endif()

        if(TARGET PNG::PNG)
            get_target_property(_png_loc PNG::PNG IMPORTED_LOCATION)
            if(_png_loc AND NOT _png_loc MATCHES "NOTFOUND")
                list(APPEND _ocv_dep_args
                    -DWITH_PNG=ON
                    "-DPNG_LIBRARY=${_png_loc}"
                    "-DPNG_PNG_INCLUDE_DIR=${EXTERNAL_INSTALL_PREFIX}/include"
                )
            endif()
        endif()

        if(TARGET TIFF::TIFF)
            get_target_property(_tiff_loc TIFF::TIFF IMPORTED_LOCATION)
            if(_tiff_loc AND NOT _tiff_loc MATCHES "NOTFOUND")
                list(APPEND _ocv_dep_args
                    -DWITH_TIFF=ON
                    "-DTIFF_LIBRARY=${_tiff_loc}"
                    "-DTIFF_INCLUDE_DIR=${EXTERNAL_INSTALL_PREFIX}/include"
                )
            endif()
        endif()

        if(TARGET OpenSSL::SSL)
            list(APPEND _ocv_dep_args
                -DWITH_OPENSSL=ON
                "-DOPENSSL_ROOT_DIR=${EXTERNAL_INSTALL_PREFIX}"
            )
        endif()

        # TBB: передаємо шлях до нашого EP TBB щоб OpenCV не взяв системний
        set(_ocv_tbb_args "")
        if(TARGET TBB::tbb)
            list(APPEND _ocv_tbb_args
                -DWITH_TBB=ON
                "-DTBB_DIR=${EXTERNAL_INSTALL_PREFIX}/lib/cmake/TBB"
                -DCMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=OFF
            )
        else()
            list(APPEND _ocv_tbb_args -DWITH_TBB=ON)
        endif()

        ep_cmake_args(_ocv_cmake_args
            # Мінімізуємо залежності для embedded/cross-compilation
            # BUILD_SHARED_LIBS=ON вже передається через ep_cmake_args()
            -DBUILD_TESTS=OFF
            -DBUILD_PERF_TESTS=OFF
            -DBUILD_EXAMPLES=OFF
            -DBUILD_DOCS=OFF
            -DWITH_GTK=OFF
            -DWITH_QT=OFF
            -DWITH_CUDA=OFF
            -DWITH_IPP=OFF
            -DOPENCV_GENERATE_PKGCONFIG=ON
            # Керовані опції (OFF за замовченням; вмикаються через OPENCV_WITH_* / OPENCV_ENABLE_*)
            -DWITH_FFMPEG=${OPENCV_WITH_FFMPEG}
            -DWITH_OPENCL=${OPENCV_WITH_OPENCL}
            -DWITH_V4L=${OPENCV_WITH_V4L2}
            -DWITH_LIBV4L=${OPENCV_WITH_LIBV4L}
            -DOPENCV_ENABLE_NONFREE=${OPENCV_ENABLE_NONFREE}
            ${_ocv_tbb_args}
            ${_ocv_contrib_arg}
            ${_ocv_dep_args}
        )

        # Init-cache для pkg-config при крос-компіляції.
        # cmake's FindPkgConfig встановлює PKG_CONFIG_LIBDIR лише для usr/lib/pkgconfig,
        # але FFmpeg лежить в usr/lib/<arch>/pkgconfig — тому не знаходиться.
        # Через -C передаємо init-cache що виставляє PKG_CONFIG_LIBDIR до старту cmake.
        set(_ocv_init_cache "${CMAKE_BINARY_DIR}/_ep_cfg/opencv-init-cache.cmake")
        if(CMAKE_CROSSCOMPILING AND CMAKE_SYSROOT AND CMAKE_LIBRARY_ARCHITECTURE)
            set(_ocv_sysroot "${CMAKE_SYSROOT}")
            set(_ocv_arch    "${CMAKE_LIBRARY_ARCHITECTURE}")
            file(WRITE "${_ocv_init_cache}"
                "set(ENV{PKG_CONFIG_SYSROOT_DIR} \"${_ocv_sysroot}\")\n"
                "set(ENV{PKG_CONFIG_LIBDIR} "
                "\"${_ocv_sysroot}/usr/lib/${_ocv_arch}/pkgconfig:"
                "${_ocv_sysroot}/usr/lib/pkgconfig:"
                "${_ocv_sysroot}/usr/share/pkgconfig\")\n")
            unset(_ocv_sysroot)
            unset(_ocv_arch)
        else()
            file(WRITE "${_ocv_init_cache}" "# native build — no extra pkg-config setup\n")
        endif()

        # BYPRODUCTS — основні модулі для Ninja
        set(_ocv_byproducts "")
        foreach(_mod IN LISTS _ocv_modules)
            list(APPEND _ocv_byproducts "${_ocv_lib_dir}/lib${_mod}.so")
        endforeach()

        if(OPENCV_USE_GIT)
            message(STATUS "[OpenCV] Джерело: git clone (${OPENCV_GIT_REPO})")
            set(_ocv_download_args
                GIT_REPOSITORY   "${OPENCV_GIT_REPO}"
                GIT_TAG          "${OPENCV_VERSION}"
                GIT_SHALLOW      ON
            )
        else()
            set(_ocv_archive_url
                "https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.tar.gz")
            message(STATUS "[OpenCV] Джерело: архів (${_ocv_archive_url})")
            set(_ocv_download_args
                URL                 "${_ocv_archive_url}"
                DOWNLOAD_EXTRACT_TIMESTAMP ON
            )
            unset(_ocv_archive_url)
        endif()

        ExternalProject_Add(opencv_ep
            ${_ocv_download_args}
            SOURCE_DIR       "${EP_SOURCES_DIR}/opencv"
            # Патч: OpenCVGenPkgconfig.cmake використовує cmake_minimum_required < 3.5,
            # що несумісно з CMake >= 3.28. Виправляємо в джерелах.
            PATCH_COMMAND
                sed -i "s/cmake_minimum_required(VERSION 2\\.[0-9][0-9.]*/cmake_minimum_required(VERSION 3.28/"
                    "${EP_SOURCES_DIR}/opencv/cmake/OpenCVGenPkgconfig.cmake"
            CMAKE_ARGS       "-C${_ocv_init_cache}" ${_ocv_cmake_args}
            BUILD_BYPRODUCTS ${_ocv_byproducts}
            LOG_DOWNLOAD     ON
            LOG_BUILD        ON
            LOG_INSTALL      ON
        )

        # Placeholder imported targets з майбутніми шляхами
        _ocv_make_imported_targets(opencv_ep)

        ep_track_cmake_file(opencv_ep "${CMAKE_CURRENT_LIST_FILE}")

        if(OPENCV_USE_GIT)
            ep_prestamp_git(opencv_ep "${EP_SOURCES_DIR}/opencv" "${OPENCV_VERSION}")
            if(OPENCV_ENABLE_CONTRIB)
                ep_prestamp_git(opencv_contrib_ep "${EP_SOURCES_DIR}/opencv_contrib" "${OPENCV_VERSION}")
            endif()
        endif()
    endif()
endif()

unset(_ocv_prefix)
unset(_ocv_lib_dir)
unset(_ocv_inc_dir)
unset(_ocv_core)
