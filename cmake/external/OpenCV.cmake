# cmake/external/OpenCV.cmake
#
# Збирає або знаходить OpenCV разом з opencv_contrib.
# opencv_contrib завантажується як окремий EP (тільки unpack, без збірки).
#
# При збірці автоматично використовує вже підключені залежності:
#   JPEG::JPEG, PNG::PNG, TIFF::TIFF, OpenSSL::SSL
#
# Provides imported targets (після першої успішної збірки — через find_package):
#   opencv_core, opencv_imgproc, opencv_imgcodecs, opencv_highgui,
#   opencv_videoio, opencv_video, opencv_features2d, opencv_calib3d,
#   opencv_objdetect, opencv_dnn, opencv_ml, opencv_flann, opencv_photo
#
# При першій збірці (бібліотека ще не встановлена) — placeholder targets
# з майбутніми шляхами. Після `cmake --build` повторна конфігурація
# автоматично перейде на реальні targets через find_package.
#
# Опції:
#   USE_SYSTEM_OPENCV      — ON: find_package в системі/sysroot
#                            OFF (за замовченням): зібрати через ExternalProject
#   OPENCV_ENABLE_CONTRIB  — ON (за замовченням): включати opencv_contrib модулі
#   OPENCV_WITH_FFMPEG     — OFF (за замовченням): увімкнути підтримку FFmpeg
#                            Потребує libavcodec/avformat/avutil/swscale-dev в sysroot.
#                            При крос-збірці: pkg-config повинен бачити ffmpeg з sysroot.
#   OPENCV_WITH_OPENCL     — OFF (за замовченням): увімкнути підтримку OpenCL
#                            Потребує OpenCL ICD loader (libOpenCL.so) і заголовків
#                            (opencl-headers) в sysroot або на хості.
#
# Кеш-змінні:
#   OPENCV_VERSION         — версія (git тег)
#   OPENCV_GIT_REPO        — URL git репозиторію OpenCV
#   OPENCV_CONTRIB_GIT_REPO — URL git репозиторію opencv_contrib

option(USE_SYSTEM_OPENCV
    "Використовувати системний OpenCV (find_package) замість збірки з джерел"
    OFF)

option(OPENCV_ENABLE_CONTRIB
    "Включати opencv_contrib модулі при збірці"
    ON)

option(OPENCV_WITH_FFMPEG
    "Збирати OpenCV з підтримкою FFmpeg (потребує ffmpeg dev-libs в sysroot/системі)"
    OFF)

option(OPENCV_WITH_OPENCL
    "Збирати OpenCV з підтримкою OpenCL (потребує OpenCL ICD loader в sysroot/системі)"
    OFF)

set(OPENCV_VERSION  "4.10.0"
    CACHE STRING "Версія OpenCV для збірки з джерел")

set(OPENCV_GIT_REPO
    "https://github.com/opencv/opencv.git"
    CACHE STRING "Git репозиторій OpenCV")

set(OPENCV_CONTRIB_GIT_REPO
    "https://github.com/opencv/opencv_contrib.git"
    CACHE STRING "Git репозиторій opencv_contrib")

# ---------------------------------------------------------------------------

set(_ocv_prefix  "${EXTERNAL_INSTALL_PREFIX}")
set(_ocv_lib_dir "${_ocv_prefix}/lib")
set(_ocv_inc_dir "${_ocv_prefix}/include/opencv4")
set(_ocv_core    "${_ocv_lib_dir}/libopencv_core.so")

# Список модулів для placeholder targets (використовується якщо бібліотека ще не зібрана)
set(_ocv_modules
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
)

# Хелпер: створює imported targets для вже встановленого OpenCV
macro(_ocv_make_imported_targets ep_name_or_empty)
    foreach(_mod ${_ocv_modules})
        if(NOT TARGET ${_mod})
            set(_mod_lib "${_ocv_lib_dir}/lib${_mod}.so")
            add_library(${_mod} SHARED IMPORTED GLOBAL)
            set_target_properties(${_mod} PROPERTIES
                IMPORTED_LOCATION             "${_mod_lib}"
                INTERFACE_INCLUDE_DIRECTORIES "${_ocv_inc_dir};${_ocv_prefix}/include"
            )
            if(ep_name_or_empty AND TARGET ${ep_name_or_empty})
                add_dependencies(${_mod} ${ep_name_or_empty})
            endif()
        endif()
    endforeach()
endmacro()

# ---------------------------------------------------------------------------

if(USE_SYSTEM_OPENCV)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(OpenCV REQUIRED)
    message(STATUS "[OpenCV] Системна бібліотека версії ${OpenCV_VERSION}")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(OpenCV QUIET HINTS "${_ocv_prefix}" NO_DEFAULT_PATH)
    if(OpenCV_FOUND)
        message(STATUS "[OpenCV] Знайдено готову бібліотеку у ${_ocv_prefix} (${OpenCV_VERSION})")

    else()
        message(STATUS "[OpenCV] Буде зібрано з джерел (версія ${OPENCV_VERSION})")

        # ── opencv_contrib: тільки clone, збірка відбувається у opencv_ep ─
        set(_contrib_src "${EP_SOURCES_DIR}/opencv_contrib")

        if(OPENCV_ENABLE_CONTRIB)
            ExternalProject_Add(opencv_contrib_ep
                GIT_REPOSITORY   "${OPENCV_CONTRIB_GIT_REPO}"
                GIT_TAG          "${OPENCV_VERSION}"
                GIT_SHALLOW      ON
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
            -DWITH_TBB=ON
            -DOPENCV_GENERATE_PKGCONFIG=ON
            # Керовані опції (OFF за замовченням; вмикаються через OPENCV_WITH_*)
            -DWITH_FFMPEG=${OPENCV_WITH_FFMPEG}
            -DWITH_OPENCL=${OPENCV_WITH_OPENCL}
            ${_ocv_contrib_arg}
            ${_ocv_dep_args}
        )

        # BYPRODUCTS — основні модулі для Ninja
        set(_ocv_byproducts "")
        foreach(_mod IN LISTS _ocv_modules)
            list(APPEND _ocv_byproducts "${_ocv_lib_dir}/lib${_mod}.so")
        endforeach()

        ExternalProject_Add(opencv_ep
            GIT_REPOSITORY   "${OPENCV_GIT_REPO}"
            GIT_TAG          "${OPENCV_VERSION}"
            GIT_SHALLOW      ON
            SOURCE_DIR       "${EP_SOURCES_DIR}/opencv"
            # Патч: OpenCVGenPkgconfig.cmake використовує cmake_minimum_required < 3.5,
            # що несумісно з CMake >= 3.28. Виправляємо в джерелах.
            PATCH_COMMAND
                sed -i "s/cmake_minimum_required(VERSION 2\\.[0-9][0-9.]*/cmake_minimum_required(VERSION 3.5/"
                    "${EP_SOURCES_DIR}/opencv/cmake/OpenCVGenPkgconfig.cmake"
            CMAKE_ARGS       ${_ocv_cmake_args}
            BUILD_BYPRODUCTS ${_ocv_byproducts}
            LOG_DOWNLOAD     ON
            LOG_BUILD        ON
            LOG_INSTALL      ON
        )

        # Placeholder imported targets з майбутніми шляхами
        _ocv_make_imported_targets(opencv_ep)
    endif()
endif()

unset(_ocv_prefix)
unset(_ocv_lib_dir)
unset(_ocv_inc_dir)
unset(_ocv_core)
