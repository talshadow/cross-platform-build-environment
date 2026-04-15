# Специфікація: ExternalProject контракти

## Огляд архітектури

```
cmake/external/
├── Common.cmake        ← спільні утиліти, підключається першим
├── ExternalDeps.cmake  ← точка входу; include() усі бібліотеки в правильному порядку
│
├── ── Незалежні ──
├── LibPng.cmake        LibJpeg.cmake   OpenSSL.cmake   Boost.cmake
├── Eigen3.cmake        Nlohmann.cmake  BoostDI.cmake   BoostSML.cmake
├── EasyProfiler.cmake  Ncnn.cmake      LibIr.cmake     GeographicLib.cmake
├── Rpclib.cmake
│
├── ── Залежності (порядок важливий) ──
├── LibTiff.cmake       ← LibJpeg, LibPng
├── OpenCV.cmake        ← LibJpeg, LibPng, LibTiff, OpenSSL
├── LibEvent.cmake      ← OpenSSL
├── LibCamera.cmake     ← LibEvent (cam утиліта)
├── LibPisp.cmake       ← LibCamera, Boost
├── RpiCamApps.cmake    ← LibCamera, Boost
├── AirSim.cmake        ← Eigen3, Rpclib
├── PhySys.cmake        ← (незалежна — PhysicsFS)
└── PhySysCpp.cmake     ← PhySys  (physfs-hpp)
cmake/SuperBuild.cmake  ← superbuild режим
```

---

## Контракт файлу Lib*.cmake

Кожен `cmake/external/Lib<Name>.cmake` зобов'язаний виконувати наведені нижче вимоги.

### 1. Надати CMake imported target

| Бібліотека | Target | Тип |
|---|---|---|
| libpng | `PNG::PNG` | `SHARED IMPORTED` |
| libjpeg-turbo | `JPEG::JPEG` | `SHARED IMPORTED` |
| libtiff | `TIFF::TIFF` | `SHARED IMPORTED` |
| OpenSSL | `OpenSSL::SSL`, `OpenSSL::Crypto` | `SHARED IMPORTED` |
| Boost | `Boost::headers`, `Boost::program_options` | `INTERFACE / SHARED` |
| OpenCV | `opencv_core`, `opencv_imgproc`, … | `SHARED IMPORTED` |
| GeographicLib | `GeographicLib::GeographicLib` | `SHARED IMPORTED` |
| Eigen3 | `Eigen3::Eigen` | `INTERFACE IMPORTED` |
| libevent | `libevent::core`, `libevent::extra` | `SHARED IMPORTED` |
| libcamera | `libcamera::libcamera` | `SHARED IMPORTED` |
| libpisp | `libpisp::libpisp` | `SHARED IMPORTED` |
| nlohmann/json | `nlohmann_json::nlohmann_json` | `INTERFACE IMPORTED` |
| boost::di | `boost::di` | `INTERFACE IMPORTED` |
| boost::sml | `boost::sml` | `INTERFACE IMPORTED` |
| easy_profiler | `easy_profiler::easy_profiler` | `SHARED IMPORTED` |
| ncnn | `ncnn::ncnn` | `SHARED IMPORTED` |
| libir | `libir::libir` | `SHARED IMPORTED` |
| rpclib | `rpclib::rpc` | `SHARED IMPORTED` |
| AirSim | `AirSim::AirLib` | `SHARED IMPORTED` |
| PhysicsFS | `PhysicsFS::PhysicsFS` | `SHARED IMPORTED` |
| physfs-hpp | `physfs-hpp::physfs-hpp` | `INTERFACE IMPORTED` |
| rpicam-apps | `rpicam_apps::camera_app` | `SHARED IMPORTED` |

Target повинен бути оголошений через `ep_imported_library()` або `ep_imported_library_from_ep()` з `Common.cmake`. Виклики ідемпотентні — повторний include() безпечний.

### 2. Підтримувати опцію USE_SYSTEM_<LIB>

```cmake
option(USE_SYSTEM_LIBFOO "Використовувати системний libfoo" OFF)
```

- `OFF` (за замовч.) → збирати через ExternalProject.
- `ON` → `find_package(Foo REQUIRED)` у системі / sysroot.

При крос-компіляції з sysroot `find_package` автоматично шукає в sysroot через `CMAKE_FIND_ROOT_PATH`.

### 3. Надати кеш-змінні версії та репозиторію

```cmake
set(LIBFOO_VERSION  "X.Y.Z" CACHE STRING "Версія для збірки (git тег)")
set(LIBFOO_GIT_REPO "https://github.com/foo/libfoo.git" CACHE STRING "Git репозиторій")
```

### 4. КРИТИЧНО: ізолювати залежності від системних бібліотек

Якщо бібліотека залежить від інших external бібліотек — **обов'язково**:

**а) Передати явні шляхи до наших артефактів:**
```cmake
-DJPEG_LIBRARY=${EXTERNAL_INSTALL_PREFIX}/lib/libjpeg.so
-DJPEG_INCLUDE_DIR=${EXTERNAL_INSTALL_PREFIX}/include
-DPNG_LIBRARY=${EXTERNAL_INSTALL_PREFIX}/lib/libpng.so
-DPNG_PNG_INCLUDE_DIR=${EXTERNAL_INSTALL_PREFIX}/include
```

**б) Бібліотечно-специфічні прапори ізоляції (де підтримуються):**
```cmake
-DWITH_JPEG=ON   # використовувати наш libjpeg
-DBUILD_JPEG=OFF # НЕ збирати bundled копію
```

Глобальний пріоритет пошуку (`find_library`, `find_package`, `find_program` тощо)
налаштовується автоматично через `ep_cmake_args()` → `ep_find_scope()`.
Вручну вказувати `CMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH` **не потрібно**.

**Наслідок порушення:** бібліотека мовчки лінкується проти системної версії —
критична помилка при крос-компіляції (ABI несумісність, неправильна архітектура).

### 5. Алгоритм вибору між кешем та збіркою

```
USE_SYSTEM_<LIB>=ON?
    ├── Так → find_package(Foo REQUIRED)          [системний / sysroot]
    └── Ні  →
            find_package(Foo QUIET
                HINTS "${EXTERNAL_INSTALL_PREFIX}"
                NO_DEFAULT_PATH)
            ├── Знайдено → target готовий, ExternalProject_Add НЕ викликається
            └── Не знайдено → ExternalProject_Add(libfoo_ep ...)
                              ep_imported_library_from_ep(Foo::Foo ...)
```

**Реалізація:**

```cmake
if(USE_SYSTEM_LIBFOO)
    find_package(Foo REQUIRED)

else()
    find_package(Foo QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(Foo_FOUND)
        message(STATUS "[LibFoo] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[LibFoo] Буде зібрано з джерел (версія ${LIBFOO_VERSION})")

        ep_cmake_args(_foo_cmake_args -DFOO_SHARED=ON -DFOO_TESTS=OFF)

        ExternalProject_Add(libfoo_ep
            GIT_REPOSITORY  "${LIBFOO_GIT_REPO}"
            GIT_TAG         "v${LIBFOO_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libfoo"
            CMAKE_ARGS      ${_foo_cmake_args}
            BUILD_BYPRODUCTS "${_foo_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(Foo::Foo libfoo_ep "${_foo_lib}" "${_foo_inc}")
    endif()
endif()
```

**Ключові правила:**
- `NO_DEFAULT_PATH` — `find_package` шукає **тільки** в `EXTERNAL_INSTALL_PREFIX`
- `QUIET` — не падати якщо не знайдено (очікувана ситуація при першій збірці)
- Якщо знайдено — `ExternalProject_Add` **не викликається**

### 6. Використовувати ep_cmake_args() для аргументів збірки

`ep_cmake_args()` автоматично передає toolchain, sysroot, компілятори, RPATH
та пріоритет пошуку бібліотек через `ep_find_scope()`.
Додаткові аргументи передаються через `ARGN`.

Якщо бібліотека потребує нестандартного scope пошуку — викликати `ep_find_scope()`
явно і передати окремо від `ep_cmake_args()`.

### 7. Прибирати локальні змінні

```cmake
unset(_foo_lib)
unset(_foo_inc)
unset(_foo_hdr)
```

---

## Common.cmake — API утиліт

### Структура директорій збірки

Всі артефакти збірки розміщуються у спільній кореневій директорії
`<BUILD_ROOT>/<project_name>/`.

**За замовчуванням** (`BUILD_ROOT` не задано → `~/build`):

```
~/build/
└── SupportRaspberryPI/
    ├── external_sources/          ← EP_SOURCES_DIR
    │   ├── libpng/
    │   ├── libjpeg/
    │   ├── libtiff/
    │   ├── openssl/
    │   ├── boost/
    │   ├── opencv/
    │   └── opencv_contrib/
    ├── external/                  ← EXTERNAL_INSTALL_PREFIX root
    │   ├── RaspberryPi4/Release/
    │   └── Ubuntu2404/Debug/
    ├── rpi4-release/              ← preset build dirs
    └── ubuntu2404-debug/
```

**З `-DBUILD_ROOT=/mnt/nvme/proj`:**

```
/mnt/nvme/proj/
└── SupportRaspberryPI/
    ├── external_sources/
    ├── external/
    │   ├── RaspberryPi4/Release/
    │   └── Ubuntu2404/Debug/
    ├── rpi4-release/
    └── ubuntu2404-debug/
```

---

### BUILD_ROOT

Cmake-параметр що замінює кореневу директорію збірки.

```bash
# за замовчуванням: ~/build/SupportRaspberryPI/
cmake --preset rpi4-release

# перевизначення кореня
cmake --preset rpi4-release -DBUILD_ROOT=/mnt/nvme/proj
```

Ім'я проєкту (`SupportRaspberryPI`) підставляється автоматично через
`CMAKE_PROJECT_NAME`.

---

### EXTERNAL_INSTALL_PREFIX

Шлях встановлення скомпільованих сторонніх бібліотек.

```
<BUILD_ROOT>/<project_name>/external/<toolchain>/<BuildType>/
```

Приклади:
- `~/build/SupportRaspberryPI/external/RaspberryPi4/Release`
- `~/build/SupportRaspberryPI/external/native/Debug`

Можна перевизначити через `-DEXTERNAL_INSTALL_PREFIX=<path>`.

Автоматично додається до `CMAKE_PREFIX_PATH` і `CMAKE_FIND_ROOT_PATH`.

---

### EP_SOURCES_DIR

Спільна директорія git-клонів сорців для всіх toolchain.

```
<BUILD_ROOT>/<project_name>/external_sources/
```

**Ключова властивість:** репозиторій клонується **один раз** і повторно
використовується при збірці під будь-який toolchain чи build type.
Компіляція та встановлення — окремі для кожної конфігурації.

Можна перевизначити через `-DEP_SOURCES_DIR=<path>`.

Кожен `ExternalProject_Add` передає `SOURCE_DIR "${EP_SOURCES_DIR}/<libname>"`.
Шаблон іменування підтеки — ім'я бібліотеки в нижньому регістрі без версії.

---

### ep_cmake_args(out_var [extra...])

Формує список аргументів для `ExternalProject_Add(CMAKE_ARGS ...)`.

Автоматично включає:
- `-DCMAKE_BUILD_TYPE`
- `-DCMAKE_INSTALL_PREFIX=${EXTERNAL_INSTALL_PREFIX}`
- `-DBUILD_SHARED_LIBS=ON`
- результат `ep_find_scope()` — пріоритет пошуку бібліотек
- `-DCMAKE_TOOLCHAIN_FILE` (якщо задано)
- `-DCMAKE_C_COMPILER`, `-DCMAKE_CXX_COMPILER`
- `-DCMAKE_SYSROOT`, `-DRPI_SYSROOT`, `-DYOCTO_SDK_SYSROOT` (якщо задано)
- `-DCMAKE_AR`, `-DCMAKE_RANLIB`, `-DCMAKE_STRIP`, `-DCMAKE_LINKER`
- `-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib` (якщо `USE_ORIGIN_RPATH=ON`)

Додаткові аргументи передаються через `ARGN`.

---

### ep_find_scope(out_var)

Повертає `CMAKE_ARGS` для пріоритету пошуку в ExternalProject суб-збірках.
Охоплює `find_library()`, `find_path()`, `find_package()`, `find_program()`.

| Умова | Пріоритет |
|---|---|
| З sysroot (крос) | `prefix → sysroot` (система повністю виключена) |
| Без sysroot (нативна) | `prefix → система` (звичайні правила після prefix) |

`find_program()` при крос-компіляції — режим `NEVER` (хост-інструменти завжди
з хоста, не з sysroot).

Викликається автоматично з `ep_cmake_args()`. Для нестандартного scope:

```cmake
ep_find_scope(_scope_args)
ExternalProject_Add(libfoo_ep
    CMAKE_ARGS ${_foo_cmake_args} ${_scope_args}
    ...
)
```

---

### ep_imported_library(target lib_path inc_dir)

Створює `SHARED IMPORTED GLOBAL` target. Ідемпотентний.

```cmake
ep_imported_library(PNG::PNG
    "${EXTERNAL_INSTALL_PREFIX}/lib/libpng.so"
    "${EXTERNAL_INSTALL_PREFIX}/include"
)
```

---

### ep_imported_interface(target inc_dir)

Створює `INTERFACE IMPORTED GLOBAL` target (header-only). Ідемпотентний.

---

### ep_imported_library_from_ep(target ep_name lib_path inc_dir)

Як `ep_imported_library`, але додає `add_dependencies(target ep_name)`.
Викликати **після** `ExternalProject_Add`.

---

### ep_imported_interface_from_ep(target ep_name inc_dir)

Як `ep_imported_interface`, але з залежністю від ExternalProject.

---

### _ep_collect_deps(out_var [ep_target...])

Повертає список тих EP-цілей зі списку що реально оголошені (`TARGET` існує).
Безпечний при відсутності деяких targets.

```cmake
_ep_collect_deps(_deps libjpeg_ep libpng_ep)
ExternalProject_Add(libtiff_ep DEPENDS ${_deps} ...)
```

---

### USE_ORIGIN_RPATH

`option(USE_ORIGIN_RPATH ... ON)` — вбудовує `$ORIGIN/../lib` у RPATH бінарників.
Забезпечує пошук `.so` відносно самого бінарника. Важливо для розгортання на RPi.

---

### _ep_cmake_to_meson_buildtype(out_var [cmake_build_type])

Перетворює значення `CMAKE_BUILD_TYPE` у відповідний тип збірки Meson.

```cmake
_ep_cmake_to_meson_buildtype(_bt)
# Далі: --buildtype=${_bt}
```

| CMAKE_BUILD_TYPE | Meson buildtype |
|---|---|
| `Debug` | `debug` |
| `Release` | `release` |
| `RelWithDebInfo` | `debugoptimized` |
| `MinSizeRel` | `minsize` |
| будь-яке інше | `debug` |

Якщо другий аргумент не переданий — використовується `CMAKE_BUILD_TYPE`.

---

### _ep_require_meson()

Перевіряє наявність `meson` та `ninja` в `PATH`.
При відсутності зупиняє конфігурацію з `FATAL_ERROR` та підказкою:

```
[EP] meson не знайдено. Встановіть:
  Ubuntu/Debian : sudo apt install meson ninja-build
  Arch/CachyOS  : sudo pacman -S meson ninja
```

Викликати перед `ExternalProject_Add` для бібліотек на базі Meson
(LibCamera, LibPisp, RpiCamApps).

---

### _ep_require_python_modules(module1 [module2 ...])

Перевіряє наявність Python-модулів через `python3 -c "import <module>"`.
При відсутності — `FATAL_ERROR` з підказками по кожному модулю окремо.

```cmake
_ep_require_python_modules(yaml ply)
```

Підказки для відомих модулів:

| Модуль | Ubuntu/Debian | Arch/CachyOS |
|---|---|---|
| `yaml` | `sudo apt install python3-yaml` | `sudo pacman -S python-yaml` |
| `ply` | `sudo apt install python3-ply` | `sudo pacman -S python-ply` |

Ці модулі є HOST-інструментами (генератор IPA protocol у LibCamera) —
вони виконуються на хості під час збірки та не потрапляють у sysroot.

---

## Meson-based ExternalProject

Деякі бібліотеки використовують систему збірки Meson (LibCamera, LibPisp, RpiCamApps).
Для них `ExternalProject_Add` не використовує `CMAKE_ARGS`, а потребує окремого шаблону:

```cmake
_ep_require_meson()
_ep_cmake_to_meson_buildtype(_meson_bt)

ExternalProject_Add(libfoo_ep
    ...
    CONFIGURE_COMMAND
        env PKG_CONFIG_PATH=${EXTERNAL_INSTALL_PREFIX}/lib/pkgconfig:${EXTERNAL_INSTALL_PREFIX}/share/pkgconfig
        ${_meson_prog} setup
            --prefix=${EXTERNAL_INSTALL_PREFIX}
            --libdir=lib
            --buildtype=${_meson_bt}
            <BINARY_DIR>
            <SOURCE_DIR>
    BUILD_COMMAND
        ${_ninja_prog} -C <BINARY_DIR> -j${_EP_NPROC}
    INSTALL_COMMAND
        ${_ninja_prog} -C <BINARY_DIR> install
    BUILD_BYPRODUCTS "${_foo_lib}"
    ...
)
```

**Важливо:**
- `<BINARY_DIR>` і `<SOURCE_DIR>` — без лапок (CMake роздільник аргументів)
- `-Dkey=${var}` — без зовнішніх лапок (інакше cmake розбиває на два аргументи)
- `PKG_CONFIG_PATH` через `env` — забезпечує видимість наших `.pc` файлів для Meson

---

## Порядок залежностей у ExternalDeps.cmake

```
LibPng     ──┐
LibJpeg    ──┼──▶ LibTiff ──┐
             │               └──▶ OpenCV
OpenSSL    ──┘──────────────────▶ OpenCV
                 OpenSSL ────────▶ LibEvent ──▶ LibCamera
LibCamera  ──┐
             ├──▶ LibPisp
Boost      ──┤
             └──▶ RpiCamApps
Eigen3     ──┐
             ├──▶ AirSim
Rpclib     ──┘
PhySys     ──────▶ PhySysCpp
```

Незалежні бібліотеки (без залежностей між собою):
`LibPng`, `LibJpeg`, `OpenSSL`, `Boost`, `Eigen3`, `GeographicLib`,
`Nlohmann`, `BoostDI`, `BoostSML`, `EasyProfiler`, `Ncnn`, `LibIr`, `Rpclib`, `PhySys`

Порядок `include()` у `ExternalDeps.cmake`:
1. `Common.cmake`
2. Незалежні бібліотеки (включно з `Rpclib.cmake`)
3. `LibTiff.cmake` (залежить від LibJpeg + LibPng)
4. `OpenCV.cmake` (залежить від LibJpeg, LibPng, LibTiff, OpenSSL)
5. `LibEvent.cmake` (залежить від OpenSSL)
6. `LibCamera.cmake` (залежить від LibEvent через `cam` утиліту)
7. `LibPisp.cmake`, `RpiCamApps.cmake` (залежать від LibCamera + Boost)
8. `AirSim.cmake` (залежить від Eigen3 + Rpclib)
9. `PhySys.cmake`, `PhySysCpp.cmake`

> **Важливо:** правильний порядок збірки забезпечується двома речами разом:
> 1. Порядок `include()` у `ExternalDeps.cmake` — гарантує що cmake-targets оголошені до використання.
> 2. Явний `DEPENDS` у `ExternalProject_Add` всередині **того самого** `Lib*.cmake` —
>    гарантує що `ninja -jN` не запустить збірку до завершення залежностей.
>
> Обидва механізми живуть разом: `ExternalDeps.cmake` викликає `include(LibTiff.cmake)`,
> а `LibTiff.cmake` сам містить і `ExternalProject_Add(libtiff_ep DEPENDS ...)`.

```cmake
# ExternalDeps.cmake — лише порядок include()
include("${_ep_dir}/LibJpeg.cmake")   # оголошує libjpeg_ep
include("${_ep_dir}/LibPng.cmake")    # оголошує libpng_ep
include("${_ep_dir}/LibTiff.cmake")   # всередині: DEPENDS libjpeg_ep libpng_ep

# LibTiff.cmake — DEPENDS у тому ж файлі де живе ExternalProject_Add
_ep_collect_deps(_tiff_deps libjpeg_ep libpng_ep)
ExternalProject_Add(libtiff_ep
    DEPENDS ${_tiff_deps}
    ...
)
```

---

## SuperBuild.cmake

Активується через `-DSUPERBUILD=ON`.

```cmake
# CMakeLists.txt
if(SUPERBUILD)
    include(cmake/SuperBuild.cmake)
    return()
endif()
```

### Що робить SuperBuild

1. Підключає `ExternalDeps.cmake` → оголошує EP для кожної бібліотеки.
2. Оголошує основний проєкт як `ExternalProject_Add(main_project_ep ...)` з `DEPENDS` на всі EP бібліотек.
3. Передає в основний проєкт: toolchain, sysroot, компілятори, `BUILD_TESTS`, санітайзери, `USE_SYSTEM_*`.
4. `BUILD_ALWAYS ON` — основний проєкт перебудовується при кожному `cmake --build`.

### Кешування в CI

```bash
# Перший запуск: збирає deps і основний проєкт
cmake -DSUPERBUILD=ON --preset rpi4-release -DRPI_SYSROOT=/srv/sysroot
cmake --build build/rpi4-release

# Кешувати між CI-запусками:
#   build/External/RaspberryPi4/Release/  ← deps (кешуються)
#   build/rpi4-release/main_project/      ← основний проєкт (завжди перебудовується)
```

---

## Кроки додавання нової бібліотеки

1. Створити `cmake/external/LibNew.cmake` за шаблоном:

```cmake
# cmake/external/LibNew.cmake
# Provides: New::New

option(USE_SYSTEM_LIBNEW "Використовувати системний libnew" OFF)

set(LIBNEW_VERSION  "X.Y.Z" CACHE STRING "Версія libnew (git тег)")
set(LIBNEW_GIT_REPO "https://github.com/owner/libnew.git" CACHE STRING "Git репозиторій")

set(_new_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libnew.so")
set(_new_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_LIBNEW)
    find_package(New REQUIRED)
    message(STATUS "[LibNew] Системна бібліотека: ${NEW_LIBRARIES}")

else()
    find_package(New QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(New_FOUND)
        message(STATUS "[LibNew] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[LibNew] Буде зібрано з джерел (версія ${LIBNEW_VERSION})")

        ep_cmake_args(_new_cmake_args
            -DLIBNEW_BUILD_SHARED=ON
            -DLIBNEW_BUILD_TESTS=OFF
        )

        ExternalProject_Add(libnew_ep
            GIT_REPOSITORY  "${LIBNEW_GIT_REPO}"
            GIT_TAG         "v${LIBNEW_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libnew"
            CMAKE_ARGS      ${_new_cmake_args}
            BUILD_BYPRODUCTS "${_new_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(New::New libnew_ep "${_new_lib}" "${_new_inc}")
    endif()
endif()

unset(_new_lib)
unset(_new_inc)
```

2. Додати `include("${_ep_dir}/LibNew.cmake")` у `ExternalDeps.cmake` у правильному місці за залежностями.

3. Якщо нова бібліотека є залежністю для іншої — передати через `_ep_collect_deps()`:

```cmake
_ep_collect_deps(_new_deps libnew_ep)
ExternalProject_Add(libother_ep DEPENDS ${_new_deps} ...)
```

4. Якщо використовується SuperBuild — додати `libnew_ep` до списку `_sb_all_lib_eps` у `SuperBuild.cmake`.

5. Якщо є опція `USE_SYSTEM_LIBNEW` — додати до циклу передачі прапорів у `SuperBuild.cmake`:

```cmake
# У SuperBuild.cmake список _lib IN ITEMS ...
foreach(_lib IN ITEMS LIBPNG LIBJPEG LIBTIFF BOOST OPENSSL OPENCV LIBNEW)
```
