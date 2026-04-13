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

Використовуй такий шаблон:

```cmake
# cmake/external/<LibName>.cmake
#
# <Короткий опис бібліотеки>
#
# Provides imported target:
#   <Namespace>::<Name>  — SHARED IMPORTED
#
# Опції:
#   USE_SYSTEM_<LIBNAME>  — ON: find_package / OFF (default): ExternalProject
#
# Кеш-змінні:
#   <LIBNAME>_VERSION, <LIBNAME>_URL, <LIBNAME>_URL_HASH

option(USE_SYSTEM_<LIBNAME>
    "Використовувати системну <LibName> замість збірки з джерел"
    OFF)

set(<LIBNAME>_VERSION  "x.y.z"  CACHE STRING "Версія <LibName>")
set(<LIBNAME>_URL      "https://..."  CACHE STRING "URL архіву <LibName>")
set(<LIBNAME>_URL_HASH ""  CACHE STRING "SHA256 хеш (порожньо = не перевіряти)")

set(_lib "${EXTERNAL_INSTALL_PREFIX}/lib/lib<name>.so")
set(_inc "${EXTERNAL_INSTALL_PREFIX}/include")
set(_hdr "${EXTERNAL_INSTALL_PREFIX}/include/<name>.h")

if(USE_SYSTEM_<LIBNAME>)
    find_package(<CMakeFindName> REQUIRED)
    message(STATUS "[<LibName>] Системна: ${<Var>_LIBRARIES}")
else()
    if(EXISTS "${_lib}" AND EXISTS "${_hdr}")
        message(STATUS "[<LibName>] Знайдено у ${EXTERNAL_INSTALL_PREFIX}")
        ep_imported_library(<Namespace>::<Name> "${_lib}" "${_inc}")
    else()
        message(STATUS "[<LibName>] Буде зібрано з джерел (${<LIBNAME>_VERSION})")

        set(_hash_arg "")
        if(<LIBNAME>_URL_HASH)
            set(_hash_arg URL_HASH "SHA256=${<LIBNAME>_URL_HASH}")
        endif()

        ep_cmake_args(_cmake_args
            -DSOME_OPTION=ON
        )

        # Залежності від інших EP (якщо є)
        _ep_collect_deps(_ep_deps libpng_ep libjpeg_ep)  # <- вказати реальні

        ExternalProject_Add(<libname>_ep
            URL             "${<LIBNAME>_URL}"
            ${_hash_arg}
            CMAKE_ARGS      ${_cmake_args}
            BUILD_BYPRODUCTS "${_lib}"
            ${_ep_deps}
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(
            <Namespace>::<Name> <libname>_ep "${_lib}" "${_inc}")
    endif()
endif()

unset(_lib)
unset(_inc)
unset(_hdr)
```

**Особливі випадки:**
- **Header-only**: замість `ep_imported_library` використовуй `ep_imported_interface` / `ep_imported_interface_from_ep`, тип target — `INTERFACE IMPORTED`
- **Не-CMake збірка** (autotools/make/custom): замість `CMAKE_ARGS` вказуй явні `CONFIGURE_COMMAND`, `BUILD_COMMAND`, `INSTALL_COMMAND`. Дивись `OpenSSL.cmake` як зразок
- **b2/Boost-подібні**: дивись `Boost.cmake` — генерація user-config.jam для крос-компіляції

### 2. Визнач залежності між бібліотеками

Перевір чи нова бібліотека залежить від вже існуючих:
- libpng_ep, libjpeg_ep, libtiff_ep, openssl_ep, boost_ep, opencv_ep

Якщо залежить — додай `_ep_collect_deps(_ep_deps ...)` і `${_ep_deps}` в `ExternalProject_Add`.
Також передай шляхи до залежних бібліотек через CMake args якщо потрібно.

### 3. Додай include до `cmake/external/ExternalDeps.cmake`

Встав рядок у правильному місці (після залежностей, перед залежними):

```cmake
include("${_ep_dir}/<LibName>.cmake")
```

### 4. Додай EP-ціль до `cmake/SuperBuild.cmake`

У список `_sb_all_lib_eps` додай `<libname>_ep`.

### 5. Оновити пам'ять

Оновити файл `/home/tal/.claude/projects/-home-tal-projects-SupportRaspberryPI/memory/project_third_party_skill.md`:
- Додати рядок у таблицю бібліотек
- Оновити список версій

## Важливі деталі архітектури

- **EXTERNAL_INSTALL_PREFIX** за замовченням: `../External/<toolchain>/<BuildType>` відносно CMAKE_BINARY_DIR
  - Де `<toolchain>` — ім'я файлу toolchain без .cmake (або `native`)
  - Приклад: `build/External/RaspberryPi4/Release/`
- **Крос-компіляція**: `ep_cmake_args()` автоматично передає CMAKE_TOOLCHAIN_FILE, CMAKE_C/CXX_COMPILER, CMAKE_SYSROOT, RPI_SYSROOT, YOCTO_SDK_SYSROOT, CMAKE_AR/RANLIB/STRIP
- **RPATH**: `$ORIGIN/../lib` через USE_ORIGIN_RPATH (передається ep_cmake_args)
- **Toolchain завантажується двічі** в CMake — не використовуй FATAL_ERROR без перевірки CMAKE_CROSSCOMPILING

## Утиліти (Common.cmake)

```cmake
ep_cmake_args(out_var [extra args])        # CMake args з toolchain/sysroot/RPATH
ep_imported_library(target lib inc)        # SHARED IMPORTED
ep_imported_interface(target inc)          # INTERFACE IMPORTED (header-only)
ep_imported_library_from_ep(t ep lib inc)  # SHARED + add_dependencies
ep_imported_interface_from_ep(t ep inc)    # INTERFACE + add_dependencies
_ep_collect_deps(out_var ep1 ep2...)       # DEPENDS arg для ExternalProject_Add
```

## Перевірка

Після створення файлів перевір:
1. `grep -r "<LibName>" cmake/external/ExternalDeps.cmake` — є include?
2. `grep -r "<libname>_ep" cmake/SuperBuild.cmake` — є в списку?
3. Чи правильний порядок includes в ExternalDeps.cmake (залежності раніше залежних)?
