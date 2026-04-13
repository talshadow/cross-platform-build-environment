# cmake/SuperBuild.cmake
#
# Superbuild режим: будує всі сторонні залежності через ExternalProject,
# а потім основний проєкт — теж як ExternalProject.
#
# Активується через:
#   cmake -DSUPERBUILD=ON -B build-super ...
#   cmake --build build-super
#
# Переваги superbuild над inline режимом:
#   - Чистіше розділення між deps та основним проєктом
#   - find_package в основному проєкті завжди працює (deps вже встановлені)
#   - Зручно для CI: один раз зібрав deps — кешуй між запусками
#
# При зміні коду основного проєкту повторний cmake --build перебудовує
# тільки основний проєкт (deps кешовані в EXTERNAL_INSTALL_PREFIX).
#
# Підключається з CMakeLists.txt:
#   if(SUPERBUILD)
#       include(cmake/SuperBuild.cmake)
#       return()
#   endif()

cmake_minimum_required(VERSION 3.20)
include(ExternalProject)

message(STATUS "=== SUPERBUILD режим ===")
message(STATUS "Source dir   : ${CMAKE_SOURCE_DIR}")
message(STATUS "Binary dir   : ${CMAKE_BINARY_DIR}")

# Підключаємо Common.cmake та всі файли бібліотек.
# Common.cmake встановлює EXTERNAL_INSTALL_PREFIX — виводимо його ПІСЛЯ.
# Вони оголосять ExternalProject_Add для тих бібліотек що ще не зібрані.
include("${CMAKE_SOURCE_DIR}/cmake/external/ExternalDeps.cmake")

message(STATUS "Deps prefix  : ${EXTERNAL_INSTALL_PREFIX}")

# ---------------------------------------------------------------------------
# Збираємо список EP-цілей що реально оголошені (залежності main project)
# ---------------------------------------------------------------------------
set(_sb_all_lib_eps
    libpng_ep
    libjpeg_ep
    libtiff_ep
    openssl_ep
    boost_ep
    opencv_contrib_ep
    opencv_ep
)

set(_sb_existing_eps "")
foreach(_ep ${_sb_all_lib_eps})
    if(TARGET ${_ep})
        list(APPEND _sb_existing_eps ${_ep})
    endif()
endforeach()

message(STATUS "[SuperBuild] ExternalProject цілі: ${_sb_existing_eps}")

# ---------------------------------------------------------------------------
# Формуємо аргументи для основного проєкту
# ---------------------------------------------------------------------------
set(_sb_main_cmake_args
    -DSUPERBUILD=OFF
    -DEXTERNAL_INSTALL_PREFIX=${EXTERNAL_INSTALL_PREFIX}
    -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
    -DUSE_ORIGIN_RPATH=${USE_ORIGIN_RPATH}
    # Опції збірки основного проєкту
    -DBUILD_TESTS=${BUILD_TESTS}
    -DENABLE_ASAN=${ENABLE_ASAN}
    -DENABLE_UBSAN=${ENABLE_UBSAN}
    -DENABLE_TSAN=${ENABLE_TSAN}
    -DENABLE_LTO=${ENABLE_LTO}
)

# Передаємо toolchain
if(CMAKE_TOOLCHAIN_FILE)
    list(APPEND _sb_main_cmake_args
        -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE})
endif()
if(CMAKE_C_COMPILER)
    list(APPEND _sb_main_cmake_args -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER})
endif()
if(CMAKE_CXX_COMPILER)
    list(APPEND _sb_main_cmake_args -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER})
endif()
if(CMAKE_SYSROOT)
    list(APPEND _sb_main_cmake_args -DCMAKE_SYSROOT=${CMAKE_SYSROOT})
endif()
if(RPI_SYSROOT)
    list(APPEND _sb_main_cmake_args -DRPI_SYSROOT=${RPI_SYSROOT})
endif()
if(YOCTO_SDK_SYSROOT)
    list(APPEND _sb_main_cmake_args -DYOCTO_SDK_SYSROOT=${YOCTO_SDK_SYSROOT})
endif()

# Передаємо прапори USE_SYSTEM_* (щоб основний проєкт не намагався будувати зайве)
foreach(_lib IN ITEMS LIBPNG LIBJPEG LIBTIFF BOOST OPENSSL OPENCV)
    if(DEFINED USE_SYSTEM_${_lib})
        list(APPEND _sb_main_cmake_args
            -DUSE_SYSTEM_${_lib}=${USE_SYSTEM_${_lib}})
    endif()
endforeach()

# ---------------------------------------------------------------------------
# Основний проєкт як ExternalProject
# ---------------------------------------------------------------------------
set(_sb_main_depends "")
if(_sb_existing_eps)
    set(_sb_main_depends DEPENDS ${_sb_existing_eps})
endif()

ExternalProject_Add(main_project_ep
    SOURCE_DIR  "${CMAKE_SOURCE_DIR}"
    BINARY_DIR  "${CMAKE_BINARY_DIR}/main_project"
    CMAKE_ARGS  ${_sb_main_cmake_args}
    ${_sb_main_depends}
    # Не встановлюємо основний проєкт — він збирається in-place
    INSTALL_COMMAND ""
    # Завжди перебудовуємо якщо викликано cmake --build
    BUILD_ALWAYS ON
    LOG_CONFIGURE ON
    LOG_BUILD     ON
)

message(STATUS "[SuperBuild] Для збірки: cmake --build ${CMAKE_BINARY_DIR}")
message(STATUS "[SuperBuild] Результат основного проєкту: ${CMAKE_BINARY_DIR}/main_project/")
