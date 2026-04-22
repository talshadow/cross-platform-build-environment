# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Призначення проєкту

Інфраструктурний CMake проєкт: toolchain файли, CMake модулі та скрипти для
крос-компіляції C/C++ під Raspberry Pi (всі варіанти) і Yocto Linux з
host-систем Ubuntu 20.04 / 24.04.

## Команди збірки

```bash
# Список пресетів
cmake --list-presets

# Конфігурація + збірка (через пресет)
cmake --preset rpi4-release -DRPI_SYSROOT=/srv/rpi4-sysroot
cmake --build --preset rpi4-release

# Через скрипт-обгортку
./scripts/build-system-build.sh rpi4-release -DRPI_SYSROOT=/srv/rpi4-sysroot

# Без пресетів (явний toolchain)
cmake -B build/rpi4 \
    -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/RaspberryPi4.cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DRPI_SYSROOT=/srv/rpi4-sysroot
cmake --build build/rpi4 -j$(nproc)
```

## Тести (тільки нативні пресети)

```bash
ctest --preset native-debug
ctest --preset native-debug -R <test_name>
ctest --preset native-debug --output-on-failure
```

## Отримання sysroot

```bash
# RPi — через Docker (не потрібен фізичний RPi)
./scripts/build-system-get-sysroot-rpi.sh --method docker --arch arm64 --dest /srv/rpi4-sysroot

# З додатковими пакетами (напр. для libopencv, libboost тощо)
./scripts/build-system-get-sysroot-rpi.sh --method docker --arch arm64 --dest /srv/rpi4-sysroot \
    --extra-packages "libopencv-dev,libboost-all-dev"

# RPi — з образу .img
sudo ./scripts/build-system-get-sysroot-rpi.sh --method image --image rpi.img.xz --dest /srv/rpi4-sysroot

# RPi — з живого пристрою
./scripts/build-system-get-sysroot-rpi.sh --method live --host 192.168.1.100 --dest /srv/rpi4-sysroot

# Yocto — встановити SDK
./scripts/build-system-get-sysroot-yocto.sh --method sdk --installer ./poky-*.sh
source /opt/poky/<ver>/environment-setup-<target>-poky-linux
```

## Структура

```
cmake/toolchains/   — toolchain файли для кожної платформи
cmake/modules/      — CompilerWarnings, Sanitizers, CrossCompileHelpers, GitVersion, StripDebug, BinaryDeps
cmake/external/     — сторонні бібліотеки через ExternalProject (23 бібліотеки; див. build-system-spec-external.md)
cmake/SuperBuild.cmake — superbuild режим
scripts/            — install-toolchains, get-sysroot-*, sync-sysroot, build, deploy
docs/               — build-system-overview.md, build-system-toolchains.md, build-system-getting-started.md
src/                — вихідний код (CMakeLists.txt-заглушка)
tests/              — тести GTest (CMakeLists.txt-заглушка)
```

## Пресети CMake

| Пресет | Платформа | Тип |
|---|---|---|
| `native-debug/release/relwithdebinfo` | системний компілятор | нативний |
| `native-asan` | системний компілятор + ASAN + UBSAN | нативний |
| `clang-debug/release/relwithdebinfo` | системний Clang | нативний |
| `clang-asan` | Clang + ASAN + UBSAN | нативний |
| `clang-tsan` | Clang + ThreadSanitizer | нативний |
| `clang18-debug/release/asan` | Clang 18 (фіксована версія) | нативний |
| `rpi4-debug/release/relwithdebinfo` | Pi 4/400/CM4, Cortex-A72 | крос |
| `rpi5-debug/release/relwithdebinfo` | Pi 5, Cortex-A76 | крос |
| `yocto-debug/release/relwithdebinfo` | Yocto (будь-яка arch) | крос |

## Ключові CMake змінні

| Змінна | Файл | Призначення |
|---|---|---|
| `RPI_SYSROOT` | RaspberryPi*.cmake | Шлях до sysroot RPi |
| `RPI<N>_TOOLCHAIN_PREFIX` | RaspberryPi*.cmake | Префікс компілятора (за замовч. `aarch64-linux-gnu`; для CT-NG toolchain може бути `aarch64-unknown-linux-gnu` — multiarch-триплет sysroot визначається автоматично) |
| `YOCTO_SDK_SYSROOT` | Yocto.cmake | Перевизначення target sysroot |
| `UBUNTU200<4>_GCC_VERSION` | Ubuntu*.cmake | Версія GCC (9/10 або 13/14) |
| `CLANG_VERSION` | Clang.cmake | Версія Clang (напр. `18`; порожньо = системний) |
| `CLANG_USE_LLD` | Clang.cmake | Використовувати lld замість ld (OFF за замовч.) |
| `BUILD_TESTS` | CMakeLists.txt | Збирати тести (ON/OFF) |
| `ENABLE_ASAN/UBSAN/TSAN` | CMakeLists.txt | Санітайзери |
| `ENABLE_LTO` | CMakeLists.txt | Link-Time Optimization |
| `SUPERBUILD` | CMakeLists.txt | Увімкнути SuperBuild режим |
| `BUILD_ROOT` | external/Common.cmake | Коренева директорія збірки (за замовч. `~/build`) |
| `EXTERNAL_INSTALL_PREFIX` | external/Common.cmake | Префікс встановлення сторонніх бібліотек |
| `EP_SOURCES_DIR` | external/Common.cmake | Директорія кешу завантажених архівів сорців |
| `USE_SYSTEM_<LIB>` | external/*.cmake | Використати системну бібліотеку замість збірки |
| `USE_ORIGIN_RPATH` | external/Common.cmake | Вбудовувати $ORIGIN RPATH (ON за замовч.) |

## Додавання модулів до власного проєкту

```cmake
list(APPEND CMAKE_MODULE_PATH "<шлях>/cmake/modules")
include(CompilerWarnings)
include(Sanitizers)
include(CrossCompileHelpers)
include(GitVersion)
include(BinaryDeps)
include(CmakeEnum)

target_enable_warnings(my_target STRICT)
target_enable_sanitizers(my_target ASAN UBSAN)
cross_detect_platform()  # виставляє PLATFORM_NAME, PLATFORM_RPI, PLATFORM_YOCTO,
                         # PLATFORM_ARM, PLATFORM_X86_64, PLATFORM_CROSS_COMPILE
cross_get_target_info()  # діагностичний вивід конфігурації + платформи

git_get_version(PROJECT_VERSION)    # з git тегу NNN.NNN.NNN.NNN, FALLBACK="0.0.0.0"
git_get_commit_hash(GIT_HASH)       # скорочений хеш HEAD (7 символів)

ep_check_binary_deps("/path/to/binary" DEPS)  # рекурсивний аналіз залежностей

declare_cmake_enum(MY_MODE "Release" "Режим" Debug Release MinSizeRel)
validate_cmake_enum(MY_MODE)               # FATAL_ERROR якщо значення поза списком
```

## Алгоритм Lib*.cmake (USE_SYSTEM=OFF)

```
find_package(Foo QUIET HINTS "${EXTERNAL_INSTALL_PREFIX}" NO_DEFAULT_PATH)
├── Знайдено → target готовий, ExternalProject_Add НЕ викликається
└── Не знайдено → ExternalProject_Add(...) + ep_imported_library_from_ep(...)
```

`NO_DEFAULT_PATH` — шукати тільки в наших артефактах, не в системі.
`QUIET` — не падати якщо не знайдено (нормально при першій збірці).

## КРИТИЧНА ВИМОГА: ізоляція залежностей ExternalProject

**Кожна бібліотека при збірці повинна використовувати ВИКЛЮЧНО наші артефакти
з `EXTERNAL_INSTALL_PREFIX` — системні бібліотеки повністю виключені.**

Для кожної залежності між бібліотеками обов'язково:

1. **Передати явні шляхи** до наших артефактів:
```cmake
-DJPEG_LIBRARY=${EXTERNAL_INSTALL_PREFIX}/lib/libjpeg.so
-DJPEG_INCLUDE_DIR=${EXTERNAL_INSTALL_PREFIX}/include
```

2. **Явно вимкнути системний пошук** цих залежностей:
```cmake
-DCMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=OFF
-DCMAKE_FIND_USE_CMAKE_SYSTEM_PATH=OFF
# або бібліотечно-специфічні прапори:
-DWITH_JPEG=ON -DBUILD_JPEG=OFF   # використовувати наш, не збирати bundled
```

3. **Порядок збірки** забезпечувати через `DEPENDS` у `ExternalProject_Add`.

Порушення цієї вимоги призводить до того що бібліотека мовчки лінкується
проти системної версії — що є критичною помилкою при крос-компіляції.

## Сторонні бібліотеки

```cmake
# Підключення всіх залежностей
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/external/ExternalDeps.cmake")

# Лінкування
target_link_libraries(my_app PRIVATE PNG::PNG JPEG::JPEG OpenSSL::SSL)
target_link_libraries(my_app PRIVATE OpenCV::opencv_core OpenCV::opencv_imgproc)
target_link_libraries(my_app PRIVATE libcamera::libcamera)  # libcamera-base підтягується автоматично
```

OpenCV надає 41 таргет у просторі `OpenCV::`:
- **Core (13):** `opencv_core`, `opencv_imgproc`, `opencv_imgcodecs`, `opencv_highgui`, `opencv_videoio`, `opencv_video`, `opencv_features2d`, `opencv_calib3d`, `opencv_objdetect`, `opencv_dnn`, `opencv_ml`, `opencv_flann`, `opencv_photo`
- **Contrib (28):** `opencv_aruco`, `opencv_bgsegm`, `opencv_bioinspired`, `opencv_ccalib`, `opencv_datasets`, `opencv_dnn_objdetect`, `opencv_dnn_superres`, `opencv_dpm`, `opencv_face`, `opencv_freetype`, `opencv_fuzzy`, `opencv_hdf`, `opencv_hfs`, `opencv_img_hash`, `opencv_intensity_transform`, `opencv_line_descriptor`, `opencv_mcc`, `opencv_optflow`, `opencv_ovis`, `opencv_phase_unwrapping`, `opencv_plot`, `opencv_quality`, `opencv_rapid`, `opencv_reg`, `opencv_rgbd`, `opencv_saliency`, `opencv_sfm`, `opencv_shape`, `opencv_stereo`, `opencv_structured_light`, `opencv_superres`, `opencv_surface_matching`, `opencv_text`, `opencv_tracking`, `opencv_videostab`, `opencv_viz`, `opencv_wechat_qrcode`, `opencv_xfeatures2d`, `opencv_ximgproc`, `opencv_xobjdetect`, `opencv_xphoto`

Повний список `USE_SYSTEM_*` опцій (за замовч. `OFF`, окрім відмічених):

`USE_SYSTEM_LIBPNG`, `USE_SYSTEM_LIBJPEG`, `USE_SYSTEM_LIBTIFF`,
`USE_SYSTEM_OPENSSL`, `USE_SYSTEM_BOOST`, `USE_SYSTEM_OPENCV`,
`USE_SYSTEM_GEOGRAPHICLIB`, `USE_SYSTEM_EIGEN3`, `USE_SYSTEM_LIBEVENT`,
`USE_SYSTEM_LIBCAMERA`, `USE_SYSTEM_LIBPISP`, `USE_SYSTEM_RPCLIB`,
`USE_SYSTEM_NLOHMANN`, `USE_SYSTEM_BOOSTDI`, `USE_SYSTEM_BOOSTSML`,
`USE_SYSTEM_EASYPROFILER`, `USE_SYSTEM_NCNN`, `USE_SYSTEM_LIBFMT`, `USE_SYSTEM_LIBIR`,
`USE_SYSTEM_AIRSIM`, `USE_SYSTEM_PHYSYS`, `USE_SYSTEM_PHYSYSCPP`,
`USE_SYSTEM_RPICAMAPPS`.

SuperBuild: `-DSUPERBUILD=ON` — збирає deps і основний проєкт як окремі ExternalProject.

## Управління збіркою EP-бібліотек

Кожна бібліотека має два допоміжні таргети:

```bash
# Перебілдити бібліотеку після ручної правки сорців у EP_SOURCES_DIR
# (configure + build + install, download пропускається):
cmake --build build/rpi4-release --target opencv_ep-rebuild
cmake --build build/rpi4-release

# Перезапустити з нуля після помилки завантаження або зміни cmake-аргументів:
cmake --build build/rpi4-release --target opencv_ep-reset
cmake --build build/rpi4-release
```

| Таргет | Видаляє стампи | Коли використовувати |
|---|---|---|
| `<ep>-rebuild` | configure + build + install | Змінено сорці в `EP_SOURCES_DIR` |
| `<ep>-reset` | всі (включно з download) | Помилка завантаження, зміна cmake-аргументів |

Авторебілд при зміні `Lib*.cmake`: якщо змінено конфігурацію бібліотеки (наприклад, додано cmake-прапор) — наступний `cmake --build` автоматично перезапустить configure + rebuild без додаткових команд.

## Структура директорій збірки

```
~/build/                         ← BUILD_ROOT (за замовч. ~/build)
└── SupportRaspberryPI/
    ├── external_sources/        ← git-клони сорців (спільні для всіх toolchain)
    ├── external/                ← скомпільовані бібліотеки (per-toolchain)
    │   ├── RaspberryPi4/Release/
    │   └── native/Debug/
    ├── rpi4-release/
    └── native-debug/
```

`-DBUILD_ROOT=/mnt/nvme/proj` — перевизначає кореневу директорію збірки.

## Специфікації

- `docs/build-system-spec-presets.md` — конвенції CMakePresets.json, чеклист додавання пресету
- `docs/build-system-spec-external.md` — контракт Lib*.cmake, API Common.cmake, кроки додавання бібліотеки
- `docs/build-system-spec-toolchain.md` — обов'язкові змінні, заборони, подвійне завантаження
- `docs/build-system-spec-modules.md` — повний API: сигнатури, параметри, поведінка при помилках
- `docs/build-system-ide-setup.md` — налаштування Qt Creator і VS Code (пресети, IntelliSense, remote debug)

## Важливі особливості

- **Toolchain завантажується двічі** — не використовуйте `message(FATAL_ERROR)` в умовах, які спрацьовують при першому завантаженні. Перевіряйте `CMAKE_CROSSCOMPILING`.
- **`CMAKE_C_FLAGS_INIT` замість `CMAKE_C_FLAGS`** у toolchain — щоб не перекрити прапори користувача.
- **Абсолютні симлінки в sysroot** — автоматично виправляються скриптами `get-sysroot-*.sh` та `build-system-sync-sysroot.sh`.
- **Yocto**: SDK середовище повинно бути активоване (`source environment-setup-*`) до запуску `cmake`. Перевірка: `./scripts/build-system-get-sysroot-yocto.sh --method check`.
- **Pi 1/Zero ARMv6**: Ubuntu `arm-linux-gnueabihf` має ARMv7 baseline — для справжнього ARMv6 потрібен спеціальний toolchain від RPi Foundation.
