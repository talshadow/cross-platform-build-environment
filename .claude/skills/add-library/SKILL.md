---
name: add-library
description: Додати нову сторонню бібліотеку до проєкту через ExternalProject. Використовувати коли потрібно інтегрувати нову бібліотеку в cmake/external/.
argument-hint: [LibraryName]
---

Додай нову сторонню бібліотеку до цього CMake-проєкту за існуючим патерном.

## Назва бібліотеки

$ARGUMENTS

## Що потрібно зробити

### 1. Створи `cmake/external/<LibName>.cmake`

#### Варіант A: CMake-збірка, git-джерело (найпоширеніший, див. LibFmt.cmake, LibPng.cmake)

```cmake
# cmake/external/<LibName>.cmake
#
# <Короткий опис бібліотеки>
# https://github.com/<org>/<repo>
#
# Provides imported target:
#   <Namespace>::<Name>  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_<LIBNAME>  — ON: find_package / OFF (default): ExternalProject
#
# Кеш-змінні:
#   <LIBNAME>_VERSION, <LIBNAME>_GIT_REPO

option(USE_SYSTEM_<LIBNAME>
    "Використовувати системну <LibName> замість збірки з джерел"
    OFF)

set(<LIBNAME>_VERSION  "x.y.z"
    CACHE STRING "Версія <LibName> для збірки з джерел")

set(<LIBNAME>_GIT_REPO
    "https://github.com/<org>/<repo>.git"
    CACHE STRING "Git репозиторій <LibName>")

# ---------------------------------------------------------------------------

set(_lib "${EXTERNAL_INSTALL_PREFIX}/lib/lib<name>.so")
set(_inc "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_<LIBNAME>)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(<CMakeFindName> REQUIRED)
    message(STATUS "[<LibName>] Системна: ${<Var>_LIBRARIES}")

else()
    # ── Алгоритм: find_package → EXISTS → ExternalProject_Add ───────────────
    find_package(<CMakeFindName> QUIET HINTS "${EXTERNAL_INSTALL_PREFIX}" NO_DEFAULT_PATH)
    if(<CMakeFindName>_FOUND)
        message(STATUS "[<LibName>] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

    elseif(EXISTS "${_lib}")
        ep_imported_library(<Namespace>::<Name> "${_lib}" "${_inc}")
        message(STATUS "[<LibName>] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[<LibName>] Буде зібрано з джерел (версія ${<LIBNAME>_VERSION})")

        ep_cmake_args(_cmake_args
            -DSOME_OPTION=ON
        )

        # Залежність від іншого EP (умовно — щоб не зламати при USE_SYSTEM=ON):
        # if(TARGET zlib_ep)
        #     list(APPEND _cmake_args
        #         "-DZLIB_LIBRARY=${EXTERNAL_INSTALL_PREFIX}/lib/libz.so"
        #         "-DZLIB_INCLUDE_DIR=${EXTERNAL_INSTALL_PREFIX}/include"
        #         -DCMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=OFF
        #         -DCMAKE_FIND_USE_CMAKE_SYSTEM_PATH=OFF
        #     )
        # endif()

        _ep_collect_deps(_ep_deps zlib_ep libpng_ep)  # <- вказати реальні або видалити

        ExternalProject_Add(<libname>_ep
            GIT_REPOSITORY  "${<LIBNAME>_GIT_REPO}"
            GIT_TAG         "${<LIBNAME>_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/<libname>"
            CMAKE_ARGS      ${_cmake_args}
            DEPENDS         ${_ep_deps}
            BUILD_BYPRODUCTS "${_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(<Namespace>::<Name> <libname>_ep "${_lib}" "${_inc}")
        ep_track_cmake_file(<libname>_ep "${CMAKE_CURRENT_LIST_FILE}")
        ep_prestamp_git(<libname>_ep "${EP_SOURCES_DIR}/<libname>" "${<LIBNAME>_VERSION}")
    endif()
endif()

unset(_lib)
unset(_inc)
```

#### Варіант B: CMake-збірка, з підтримкою git / URL-архіву (USE_GIT, div. Zlib.cmake)

Додаємо опцію `<LIBNAME>_USE_GIT` і передаємо різний блок завантаження:

```cmake
option(<LIBNAME>_USE_GIT
    "Завантажувати <LibName> через git clone (OFF = архів з GitHub Releases)"
    OFF)

# ... всередині else() ExternalProject ...
if(<LIBNAME>_USE_GIT)
    set(_download_args
        GIT_REPOSITORY  "${<LIBNAME>_GIT_REPO}"
        GIT_TAG         "${<LIBNAME>_VERSION}"
        GIT_SHALLOW     ON
    )
else()
    set(_archive_url "https://github.com/<org>/<repo>/archive/refs/tags/${<LIBNAME>_VERSION}.tar.gz")
    set(_download_args
        URL                 "${_archive_url}"
        DOWNLOAD_EXTRACT_TIMESTAMP ON
    )
    unset(_archive_url)
endif()

ExternalProject_Add(<libname>_ep
    ${_download_args}
    SOURCE_DIR      "${EP_SOURCES_DIR}/<libname>"  # SOURCE_DIR — завжди, для обох варіантів
    CMAKE_ARGS      ${_cmake_args}
    BUILD_BYPRODUCTS "${_lib}"
    LOG_DOWNLOAD ON  LOG_BUILD ON  LOG_INSTALL ON
)

ep_imported_library_from_ep(<Namespace>::<Name> <libname>_ep "${_lib}" "${_inc}")
ep_track_cmake_file(<libname>_ep "${CMAKE_CURRENT_LIST_FILE}")
if(<LIBNAME>_USE_GIT)
    ep_prestamp_git(<libname>_ep "${EP_SOURCES_DIR}/<libname>" "${<LIBNAME>_VERSION}")
endif()
```

#### Варіант C: Meson-збірка (div. RpiCamApps.cmake)

```cmake
# Всередині else() / else ExternalProject_Add:
_ep_require_meson()
find_program(_<name>_meson meson)
find_program(_<name>_ninja ninja)
_ep_cmake_to_meson_buildtype(_<name>_meson_bt)
_meson_generate_cross_file(_<name>_cross_args)
_meson_write_overlay(<libname> _<name>_cross_args)

_ep_collect_deps(_ep_deps dep1_ep dep2_ep)

ExternalProject_Add(<libname>_ep
    GIT_REPOSITORY  "${<LIBNAME>_GIT_REPO}"
    GIT_TAG         "${<LIBNAME>_VERSION}"
    GIT_SHALLOW     ON
    SOURCE_DIR      "${EP_SOURCES_DIR}/<libname>"
    DEPENDS         ${_ep_deps}
    CONFIGURE_COMMAND
        env
            PKG_CONFIG_PATH=${EXTERNAL_INSTALL_PREFIX}/lib/pkgconfig:${EXTERNAL_INSTALL_PREFIX}/share/pkgconfig
        ${_<name>_meson} setup
            --reconfigure
            ${_<name>_cross_args}
            --prefix=${EXTERNAL_INSTALL_PREFIX}
            --libdir=lib
            --buildtype=${_<name>_meson_bt}
            -Dsome_option=enabled
            <BINARY_DIR>
            <SOURCE_DIR>
    BUILD_COMMAND
        ${_<name>_ninja} -C "<BINARY_DIR>" -j${_EP_NPROC}
    INSTALL_COMMAND
        ${_<name>_ninja} -C "<BINARY_DIR>" install
    BUILD_BYPRODUCTS "${_lib}"
    LOG_DOWNLOAD ON  LOG_CONFIGURE ON  LOG_BUILD ON  LOG_INSTALL ON
)

ep_imported_library_from_ep(<Namespace>::<Name> <libname>_ep "${_lib}" "${_inc}")
ep_track_cmake_file(<libname>_ep "${CMAKE_CURRENT_LIST_FILE}")
ep_prestamp_git(<libname>_ep "${EP_SOURCES_DIR}/<libname>" "${<LIBNAME>_VERSION}")

unset(_<name>_meson)
unset(_<name>_ninja)
unset(_<name>_cross_args)
```

#### Варіант D: USE_SYSTEM з pkg-config fallback (div. RpiCamApps.cmake)

Якщо `find_package` може не знайти пакет (бібліотека не має CMake-конфіга):

```cmake
if(USE_SYSTEM_<LIBNAME>)
    find_package(<CMakeFindName> QUIET)
    if(<CMakeFindName>_FOUND)
        message(STATUS "[<LibName>] Системна: <Namespace>::<Name>")
    else()
        find_package(PkgConfig QUIET)
        if(PkgConfig_FOUND)
            pkg_check_modules(<PKGNAME> IMPORTED_TARGET <pkg-config-name>)
            if(<PKGNAME>_FOUND)
                if(NOT TARGET <Namespace>::<Name>)
                    add_library(<Namespace>::<Name> INTERFACE IMPORTED GLOBAL)
                    set_property(TARGET <Namespace>::<Name>
                        APPEND PROPERTY INTERFACE_LINK_LIBRARIES PkgConfig::<PKGNAME>)
                endif()
                message(STATUS "[<LibName>] Системна (pkg-config): ${<PKGNAME>_LIBRARIES}")
            else()
                message(WARNING "[<LibName>] USE_SYSTEM_<LIBNAME>=ON але не знайдено")
            endif()
        endif()
    endif()
```

**Інші особливі випадки:**
- **Header-only**: замість `ep_imported_library` → `ep_imported_interface` / `ep_imported_interface_from_ep`, тип target — `INTERFACE IMPORTED`
- **Не-CMake збірка** (autotools/make/custom): замість `CMAKE_ARGS` → `CONFIGURE_COMMAND`, `BUILD_COMMAND`, `INSTALL_COMMAND`. Дивись `OpenSSL.cmake`
- **b2/Boost-подібні**: дивись `Boost.cmake` — генерація user-config.jam для крос-компіляції

### 2. Визнач залежності між бібліотеками

Перевір чи нова бібліотека залежить від вже існуючих EP:
- zlib_ep, libpng_ep, libjpeg_ep, libtiff_ep, openssl_ep, boost_ep, opencv_ep

Якщо залежить — використовуй умовний блок `if(TARGET dep_ep)`:

```cmake
if(TARGET zlib_ep)
    # zlib збирається як EP — передаємо явні шляхи і вимикаємо системний пошук
    list(APPEND _cmake_args
        "-DZLIB_LIBRARY=${EXTERNAL_INSTALL_PREFIX}/lib/libz.so"
        "-DZLIB_INCLUDE_DIR=${EXTERNAL_INSTALL_PREFIX}/include"
        -DCMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=OFF
        -DCMAKE_FIND_USE_CMAKE_SYSTEM_PATH=OFF
    )
endif()
```

Якщо шлях до .so відомий лише з target property (наприклад, для складних бібліотек):
```cmake
get_target_property(_dep_so Dep::Lib IMPORTED_LOCATION)
list(APPEND _cmake_args "-DDEP_LIBRARY=${_dep_so}")
```

Додай `DEPENDS ${_ep_deps}` через `_ep_collect_deps(_ep_deps dep1_ep dep2_ep)`.

### 3. Додай include до `cmake/external/ExternalDeps.cmake`

Встав рядок у правильному місці (після залежностей, перед залежними):

```cmake
include("${_ep_dir}/<LibName>.cmake")
```

### 4. Додай EP-ціль до `cmake/SuperBuild.cmake`

У список `_sb_all_lib_eps` додай `<libname>_ep`.

### 5. Оновити пам'ять

Оновити файл пам'яті проєкту (перевір шлях через MEMORY.md):
- Додати рядок у таблицю бібліотек
- Оновити список версій

## Важливі деталі архітектури

- **EXTERNAL_INSTALL_PREFIX** за замовченням: `<BUILD_ROOT>/<project>/external/<toolchain>/<BuildType>`
  - `BUILD_ROOT` за замовч. `~/build`, змінюється через `-DBUILD_ROOT=<path>`
  - `<toolchain>` — ім'я файлу toolchain без .cmake (або `native`)
- **EP_SOURCES_DIR**: `<BUILD_ROOT>/<project>/external_sources/` — сорці спільні для всіх toolchain
  - Для **git-джерела**: `SOURCE_DIR "${EP_SOURCES_DIR}/<libname>"` (git clone прямо сюди)
  - Для **URL-архіву**: `SOURCE_DIR "${EP_SOURCES_DIR}/<libname>"` + `DOWNLOAD_EXTRACT_TIMESTAMP ON` (архів розпаковується сюди; `DOWNLOAD_DIR` не використовується)
- **Три гілки кешу** (обов'язково всі три):
  1. `find_package(QUIET HINTS "${EXTERNAL_INSTALL_PREFIX}" NO_DEFAULT_PATH)` — повна cmake-конфігурація
  2. `elseif(EXISTS "${_lib}")` — .so є, cmake-конфіга немає (напр. після ручного install)
  3. `else()` — збираємо з джерел через ExternalProject_Add
- **Крос-компіляція**: `ep_cmake_args()` автоматично передає CMAKE_TOOLCHAIN_FILE, CMAKE_C/CXX_COMPILER, CMAKE_SYSROOT, RPI_SYSROOT, YOCTO_SDK_SYSROOT, CMAKE_AR/RANLIB/STRIP
- **RPATH**: `$ORIGIN/../lib` через USE_ORIGIN_RPATH (передається ep_cmake_args автоматично)
- **Toolchain завантажується двічі** в CMake — не використовуй FATAL_ERROR без перевірки CMAKE_CROSSCOMPILING

## КРИТИЧНА ВИМОГА: ізоляція залежностей

Якщо бібліотека залежить від інших external libs — **обов'язково**:
1. Передати явні шляхи: `-DFOO_LIBRARY=${EXTERNAL_INSTALL_PREFIX}/lib/libfoo.so`, `-DFOO_INCLUDE_DIR=...`
2. Вимкнути системний пошук: `-DCMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=OFF`, `-DCMAKE_FIND_USE_CMAKE_SYSTEM_PATH=OFF`
3. Загортати у `if(TARGET dep_ep)` — щоб не зламати сценарій USE_SYSTEM=ON для залежності

Порушення → мовчазне лінкування проти системної бібліотеки = критична помилка при крос-компіляції.

## Утиліти (Common.cmake)

```cmake
ep_cmake_args(out_var [extra args])               # CMake args з toolchain/sysroot/RPATH
ep_imported_library(target lib inc)               # SHARED IMPORTED (без EP залежності)
ep_imported_interface(target inc)                 # INTERFACE IMPORTED (header-only, без EP)
ep_imported_library_from_ep(t ep lib inc)         # SHARED + add_dependencies(t ep)
ep_imported_interface_from_ep(t ep inc)           # INTERFACE + add_dependencies(t ep)
_ep_collect_deps(out_var ep1 ep2...)              # список існуючих EP-цілей для DEPENDS
ep_track_cmake_file(ep_target cmake_file)         # авторебілд при зміні Lib*.cmake
ep_prestamp_git(ep_target src_dir tag)            # iterative rebuild для git-джерел
_ep_require_meson()                               # перевірити наявність meson/ninja
_meson_generate_cross_file(out_cross_args)        # cross-file для meson крос-компіляції
_meson_write_overlay(libname inout_cross_args)    # overlay з -I нашого prefix
_ep_cmake_to_meson_buildtype(out_var)             # Debug/Release → debug/release
```

## Перевірка

Після створення файлів перевір:
1. `grep -r "<LibName>" cmake/external/ExternalDeps.cmake` — є include?
2. `grep -r "<libname>_ep" cmake/SuperBuild.cmake` — є в списку?
3. Чи правильний порядок includes в ExternalDeps.cmake (залежності раніше залежних)?
4. Чи всі три гілки є: `find_package` → `elseif(EXISTS)` → `else ExternalProject`?
5. Чи є `ep_track_cmake_file()` після ExternalProject_Add?
6. Чи є `ep_prestamp_git()` для git-джерел?
7. Чи передані явні шляхи до всіх external залежностей і вимкнений системний пошук?
