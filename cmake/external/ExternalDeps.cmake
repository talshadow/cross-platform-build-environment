# cmake/external/ExternalDeps.cmake
#
# Головний файл підключення всіх сторонніх залежностей.
# Підключати з кореневого CMakeLists.txt:
#
#   include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/external/ExternalDeps.cmake")
#
# Порядок підключення важливий: залежності ідуть раніше залежних.
# LibTiff <- LibJpeg, LibPng
# OpenCV  <- LibJpeg, LibPng, LibTiff, OpenSSL
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

# ── Залежить від LibJpeg + LibPng ───────────────────────────────────────────
include("${_ep_dir}/LibTiff.cmake")

# ── Залежить від LibJpeg, LibPng, LibTiff, OpenSSL ──────────────────────────
include("${_ep_dir}/OpenCV.cmake")

unset(_ep_dir)
