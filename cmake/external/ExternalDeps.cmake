# cmake/external/ExternalDeps.cmake
#
# Головний файл підключення всіх сторонніх залежностей.
# Підключати з кореневого CMakeLists.txt:
#
#   include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/external/ExternalDeps.cmake")
#
# Порядок підключення важливий: залежності ідуть раніше залежних.
# LibTiff     <- LibJpeg, LibPng
# OpenCV      <- LibJpeg, LibPng, LibTiff, OpenSSL
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
# include("${_ep_dir}/LibIr.cmake")

# ── Залежить від LibJpeg + LibPng ───────────────────────────────────────────
include("${_ep_dir}/LibTiff.cmake")

# ── Залежить від LibJpeg, LibPng, LibTiff, OpenSSL ──────────────────────────
include("${_ep_dir}/OpenCV.cmake")

# ── Незалежна: геодезичні та картографічні обчислення ───────────────────────
include("${_ep_dir}/GeographicLib.cmake")

# ── Залежить від OpenSSL ─────────────────────────────────────────────────────
include("${_ep_dir}/LibEvent.cmake")

# ── Незалежна: камера ────────────────────────────────────────────────────────
include("${_ep_dir}/LibCamera.cmake")

# ── Залежить від LibCamera + Boost (тільки RPi 5) ───────────────────────────
include("${_ep_dir}/LibPisp.cmake")

# ── Залежить від LibCamera + Boost ──────────────────────────────────────────
include("${_ep_dir}/RpiCamApps.cmake")

# ── Незалежна: rpclib (msgpack-RPC, потрібна для AirSim) ────────────────────
include("${_ep_dir}/Rpclib.cmake")

# ── Залежить від Eigen3 + Rpclib ─────────────────────────────────────────────
include("${_ep_dir}/AirSim.cmake")

# ── Незалежні: прикладні бібліотеки ─────────────────────────────────────────
include("${_ep_dir}/PhySys.cmake")

# ── Залежить від PhySys ──────────────────────────────────────────────────────
include("${_ep_dir}/PhySysCpp.cmake")

unset(_ep_dir)
