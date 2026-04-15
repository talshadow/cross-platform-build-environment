# cmake/external/ExternalDeps.cmake
#
# Головний файл підключення всіх сторонніх залежностей.
# Підключати з кореневого CMakeLists.txt:
#
#   include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/external/ExternalDeps.cmake")
#
# Порядок підключення важливий: залежності ідуть раніше залежних.
# Тут же — явні ExternalProject_Add_StepDependencies() для кожного EP що має залежності.
# Це єдине місце де описується граф залежностей між EP.
#
# LibTiff     <- LibJpeg, LibPng
# OpenCV      <- LibJpeg, LibPng, LibTiff, OpenSSL, [opencv_contrib]
# LibEvent    <- OpenSSL
# LibCamera   <- LibEvent (cam утиліта)
# LibPisp     <- LibCamera, Boost
# RpiCamApps  <- LibCamera, Boost
# AirSim      <- Eigen3, Rpclib
# PhySysCpp   <- PhySys
#
# Кожна бібліотека управляється окремим cmake-файлом у цій директорії.
# Для додавання нової бібліотеки:
#   1. Створити cmake/external/LibNew.cmake за існуючим зразком
#   2. Додати include() нижче в правильному місці за залежностями
#   3. Додати ExternalProject_Add_StepDependencies() якщо бібліотека має залежності
#
# Примітка: використовуємо ExternalProject_Add_StepDependencies(ep build deps...)
# замість add_dependencies(ep deps...).
# add_dependencies додає залежність тільки на рівні *-done target — ninja вільний
# запустити build-крок без очікування deps якщо configure-stamp вже існує.
# ExternalProject_Add_StepDependencies(ep build ...) інжектує залежність
# безпосередньо в build-крок і гарантує правильну серіалізацію.

set(_ep_dir "${CMAKE_CURRENT_LIST_DIR}")

include("${_ep_dir}/Common.cmake")

# ── Незалежні бібліотеки ────────────────────────────────────────────────────
include("${_ep_dir}/LibPng.cmake")
include("${_ep_dir}/LibJpeg.cmake")
include("${_ep_dir}/OpenSSL.cmake")
include("${_ep_dir}/Boost.cmake")
include("${_ep_dir}/Eigen3.cmake")
include("${_ep_dir}/Nlohmann.cmake")
include("${_ep_dir}/BoostDI.cmake")
include("${_ep_dir}/BoostSML.cmake")
include("${_ep_dir}/EasyProfiler.cmake")
include("${_ep_dir}/Ncnn.cmake")
include("${_ep_dir}/Rpclib.cmake")
include("${_ep_dir}/LibFmt.cmake")
# include("${_ep_dir}/LibIr.cmake")

# ── Залежить від LibJpeg + LibPng ───────────────────────────────────────────
include("${_ep_dir}/LibTiff.cmake")
if(TARGET libtiff_ep)
    _ep_collect_deps(_deps libjpeg_ep libpng_ep)
    if(_deps)
        ExternalProject_Add_StepDependencies(libtiff_ep build ${_deps})
    endif()
endif()

# ── Залежить від LibJpeg, LibPng, LibTiff, OpenSSL ──────────────────────────
include("${_ep_dir}/OpenCV.cmake")
if(TARGET opencv_ep)
    _ep_collect_deps(_deps libjpeg_ep libpng_ep libtiff_ep openssl_ep opencv_contrib_ep)
    if(_deps)
        ExternalProject_Add_StepDependencies(opencv_ep build ${_deps})
    endif()
endif()

# ── Незалежна: геодезичні та картографічні обчислення ───────────────────────
include("${_ep_dir}/GeographicLib.cmake")

# ── Залежить від OpenSSL ─────────────────────────────────────────────────────
include("${_ep_dir}/LibEvent.cmake")
if(TARGET libevent_ep)
    _ep_collect_deps(_deps openssl_ep)
    if(_deps)
        ExternalProject_Add_StepDependencies(libevent_ep build ${_deps})
    endif()
endif()

# ── Залежить від LibEvent (cam утиліта) ──────────────────────────────────────
include("${_ep_dir}/LibCamera.cmake")
if(TARGET libcamera_ep)
    _ep_collect_deps(_deps libevent_ep)
    if(_deps)
        ExternalProject_Add_StepDependencies(libcamera_ep build ${_deps})
    endif()
endif()

# ── Залежить від LibCamera + Boost (тільки RPi 5) ───────────────────────────
include("${_ep_dir}/LibPisp.cmake")
if(TARGET libpisp_ep)
    _ep_collect_deps(_deps libcamera_ep boost_ep)
    if(_deps)
        ExternalProject_Add_StepDependencies(libpisp_ep build ${_deps})
    endif()
endif()

# ── Залежить від LibCamera + Boost ──────────────────────────────────────────
include("${_ep_dir}/RpiCamApps.cmake")
if(TARGET rpicamapps_ep)
    _ep_collect_deps(_deps libcamera_ep boost_ep)
    if(_deps)
        ExternalProject_Add_StepDependencies(rpicamapps_ep build ${_deps})
    endif()
endif()

# ── Залежить від Eigen3 + Rpclib ─────────────────────────────────────────────
include("${_ep_dir}/AirSim.cmake")
if(TARGET airsim_ep)
    _ep_collect_deps(_deps eigen3_ep rpclib_ep)
    if(_deps)
        ExternalProject_Add_StepDependencies(airsim_ep build ${_deps})
    endif()
endif()

# ── Незалежні: прикладні бібліотеки ─────────────────────────────────────────
include("${_ep_dir}/PhySys.cmake")

# ── Залежить від PhySys ──────────────────────────────────────────────────────
include("${_ep_dir}/PhySysCpp.cmake")
if(TARGET physfscpp_ep)
    _ep_collect_deps(_deps physfs_ep)
    if(_deps)
        ExternalProject_Add_StepDependencies(physfscpp_ep build ${_deps})
    endif()
endif()

unset(_deps)
unset(_ep_dir)
