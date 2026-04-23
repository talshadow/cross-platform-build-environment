# Архітектура проєкту

## Призначення

Інфраструктурний CMake проєкт: надає готові toolchain файли, CMake модулі та
допоміжні скрипти для крос-компіляції C/C++ проєктів під Raspberry Pi і
Yocto Linux з host-систем Ubuntu 20.04 / 24.04 та Arch Linux / CachyOS.

Проєкт не є застосунком — це шаблон і набір інструментів, який підключається
до вашого основного `CMakeLists.txt`.

---

## Структура файлів

Детальні специфікації:
- [build-system-spec-presets.md](build-system-spec-presets.md) — формат і конвенції CMakePresets.json
- [build-system-spec-external.md](build-system-spec-external.md) — контракти ExternalProject бібліотек
- [build-system-spec-toolchain.md](build-system-spec-toolchain.md) — контракт toolchain файлів
- [build-system-spec-modules.md](build-system-spec-modules.md) — повний API CMake модулів
- [build-system-ide-setup.md](build-system-ide-setup.md) — налаштування Qt Creator та VS Code

---

## Структура файлів

```
SupportRaspberryPI/
│
├── CMakeLists.txt              # Кореневий файл (шаблонний проєкт)
├── CMakePresets.json           # Пресети для всіх платформ
│
├── cmake/
│   ├── toolchains/
│   │   ├── common.cmake        # Спільні макроси (підключається через include())
│   │   ├── RaspberryPi1.cmake  # ARMv6 (Pi 1, Zero, Zero W)
│   │   ├── RaspberryPi2.cmake  # ARMv7-A (Pi 2)
│   │   ├── RaspberryPi3.cmake  # AArch64 Cortex-A53 (Pi 3, Zero 2W)
│   │   ├── RaspberryPi4.cmake  # AArch64 Cortex-A72 (Pi 4, 400, CM4)
│   │   ├── RaspberryPi5.cmake  # AArch64 Cortex-A76 (Pi 5)
│   │   ├── Yocto.cmake         # Yocto SDK (будь-яка архітектура)
│   │   ├── Ubuntu2004.cmake    # x86_64, GCC 9/10
│   │   ├── Ubuntu2404.cmake    # x86_64, GCC 13/14
│   │   └── Clang.cmake         # x86_64, Clang (версія через CLANG_VERSION)
│   │
│   ├── modules/
│   │   ├── CompilerWarnings.cmake    # target_enable_warnings()
│   │   ├── Sanitizers.cmake          # target_enable_sanitizers()
│   │   ├── CrossCompileHelpers.cmake # cross_check_cxx_flag(), cross_feature_check()
│   │   ├── GitVersion.cmake          # git_get_version(), git_get_commit_hash()
│   │   ├── StripDebug.cmake          # strip_debug / strip_all / strip_split targets
│   │   ├── BinaryDeps.cmake          # ep_check_binary_deps() — рекурсивний аналіз залежностей
│   │   └── InstallHelpers.cmake       # project_setup_install() — кастомна інсталяція
│   │
│   ├── external/
│   │   ├── Common.cmake        # Спільні утиліти ExternalProject
│   │   ├── ExternalDeps.cmake  # Головна точка підключення залежностей
│   │   ├── LibPng.cmake        # libpng           (PNG::PNG)
│   │   ├── LibJpeg.cmake       # libjpeg-turbo    (JPEG::JPEG, TurboJPEG::TurboJPEG)
│   │   ├── LibTiff.cmake       # libtiff           (TIFF::TIFF)
│   │   ├── OpenSSL.cmake       # OpenSSL           (OpenSSL::SSL, ::Crypto)
│   │   ├── Boost.cmake         # Boost             (Boost::headers, ::program_options)
│   │   ├── OpenCV.cmake        # OpenCV            (opencv_core, ...)
│   │   ├── GeographicLib.cmake # GeographicLib     (GeographicLib::GeographicLib)
│   │   ├── Eigen3.cmake        # Eigen3            (Eigen3::Eigen) header-only
│   │   ├── LibEvent.cmake      # libevent          (libevent::core, ::extra)
│   │   ├── LibCamera.cmake     # libcamera         (libcamera::libcamera)
│   │   ├── LibPisp.cmake       # libpisp           (libpisp::libpisp)
│   │   ├── Nlohmann.cmake      # nlohmann/json     (nlohmann_json::nlohmann_json) h-only
│   │   ├── BoostDI.cmake       # boost-ext/di      (boost::di) header-only
│   │   ├── BoostSML.cmake      # boost-ext/sml     (boost::sml) header-only
│   │   ├── EasyProfiler.cmake  # easy_profiler     (easy_profiler::easy_profiler)
│   │   ├── Ncnn.cmake          # ncnn              (ncnn::ncnn)
│   │   ├── LibFmt.cmake        # {fmt}             (fmt::fmt)
│   │   ├── LibIr.cmake         # libir             (libir::libir)
│   │   ├── Rpclib.cmake        # rpclib            (rpclib::rpc)
│   │   ├── AirSim.cmake        # AirSim client     (AirSim::AirLib) — shared
│   │   ├── PhySys.cmake        # PhysicsFS         (PhysicsFS::PhysicsFS)
│   │   ├── PhySysCpp.cmake     # physfs-hpp        (physfs-hpp::physfs-hpp) h-only
│   │   └── RpiCamApps.cmake    # rpicam-apps       (rpicam_apps::camera_app)
│   │
│   ├── SuperBuild.cmake        # Superbuild режим (всі deps + main як EP)
│   └── install_project.cmake     # cmake -P скрипт інсталяції (BinaryDeps + strip)
│
├── scripts/
│   ├── build-system-install-toolchains.sh   # Встановити крос-компілятори (apt / pacman)
│   ├── build-system-get-sysroot-rpi.sh      # Отримати sysroot для RPi (Docker/образ/SSH)
│   ├── build-system-get-sysroot-yocto.sh    # Встановити/витягнути Yocto SDK sysroot
│   ├── build-system-sync-sysroot.sh         # Синхронізувати sysroot з живого RPi
│   ├── build-system-build.sh                # Обгортка над cmake --preset
│   └── build-system-deploy.sh               # Розгортання по SSH
│
├── src/                        # Вихідний код проєкту
├── tests/                      # Тести (GTest, ctest)
│
└── docs/
    ├── build-system-overview.md             # Цей файл
    ├── build-system-toolchains.md           # Детальний опис toolchain файлів
    ├── build-system-getting-started.md      # Покрокова інструкція
    ├── build-system-ide-setup.md            # Qt Creator та VS Code: пресети, IntelliSense, remote debug
    ├── build-system-spec-presets.md         # Специфікація CMakePresets.json: конвенції, чеклист
    ├── build-system-spec-external.md        # Специфікація Lib*.cmake: контракти, API Common.cmake
    ├── build-system-spec-toolchain.md       # Специфікація toolchain файлів: вимоги, заборони
    └── build-system-spec-modules.md         # Специфікація cmake/modules: повний API
```

---

## Потік крос-компіляції

```
Host (Ubuntu / Arch / CachyOS)
│
├─ [1] build-system-install-toolchains.sh
│      apt install gcc-aarch64-linux-gnu ...     # Ubuntu
│      pacman -S aarch64-linux-gnu-gcc ...       # Arch / CachyOS
│
├─ [2] build-system-get-sysroot-rpi.sh / build-system-get-sysroot-yocto.sh
│      → /srv/rpi4-sysroot/
│           ├── lib/
│           ├── usr/include/
│           └── usr/lib/
│
├─ [3] cmake --preset rpi4-release
│      │  -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/RaspberryPi4.cmake
│      │  -DRPI_SYSROOT=/srv/rpi4-sysroot
│      │
│      └─ CMake читає toolchain:
│            CMAKE_C_COMPILER   = aarch64-linux-gnu-gcc
│            CMAKE_SYSROOT      = /srv/rpi4-sysroot
│            CMAKE_C_FLAGS_INIT = -mcpu=cortex-a72+crc+simd
│
├─ [4] cmake --build --preset rpi4-release
│      → build/rpi4-release/bin/<ваш_бінарник>  (ELF AArch64)
│
└─ [5] build-system-deploy.sh --preset rpi4-release --host 192.168.1.100
       rsync → RPi → запуск
```

---

## Принцип роботи toolchain файлів

### Що відбувається коли CMake зчитує toolchain

1. Toolchain завантажується **двічі**: під час `try_compile` тестів і при
   основній конфігурації. Тому toolchain не повинен мати побічних ефектів.

2. `CMAKE_C_FLAGS_INIT` / `CMAKE_CXX_FLAGS_INIT` — задаються **один раз**
   з toolchain і стають базою для `CMAKE_C_FLAGS`. Якщо toolchain файл
   завантажується знову — значення в кеші вже є, `CACHE INTERNAL ""` гарантує
   що вони не перезаписуються.

3. `CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER` забезпечує що при `find_program()`
   CMake знаходить програми хост-системи (cmake, python, тощо), а не
   цільової.

4. `CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY` забезпечує що `.so`/`.a`
   знаходяться тільки в sysroot, не на хості.

### Чому `CMAKE_C_FLAGS_INIT`, а не `CMAKE_C_FLAGS`

`CMAKE_C_FLAGS` — кешована змінна користувача. Перезапис з toolchain
перекриє все що користувач задав через `-DCMAKE_C_FLAGS=...`. `*_INIT`
змінні задають **початкові** значення і об'єднуються з `CMAKE_C_FLAGS`.

### Sysroot та симлінки

Після синхронізації sysroot деякі `.so` файли мають абсолютні симлінки:
```
/srv/rpi4-sysroot/usr/lib/aarch64-linux-gnu/libssl.so -> /lib/aarch64-linux-gnu/libssl.so.3
```
Посилання `/lib/...` — абсолютне відносно **хост-системи**, а не sysroot.
Лінкер крос-компілятора його не знайде.

Скрипти `build-system-sync-sysroot.sh` та `build-system-get-sysroot-rpi.sh` автоматично перетворюють
такі посилання на відносні через `fixup_symlinks()`.

---

## CMakePresets.json — структура пресетів

```
base (hidden)
│   generator: Ninja
│   binaryDir: build/${presetName}
│   CMAKE_EXPORT_COMPILE_COMMANDS: ON
│
├── base-cross (hidden)
│   inherits: base
│   BUILD_TESTS: OFF
│
├── native-debug / native-release / native-asan
│   CMAKE_BUILD_TYPE: Debug / Release
│
├── clang-debug / clang-asan / clang-tsan
│   toolchainFile: Clang.cmake
│
├── rpi4-debug / rpi4-release
│   inherits: base-cross
│   toolchainFile: RaspberryPi4.cmake
│
├── rpi5-debug / rpi5-release
│   inherits: base-cross
│   toolchainFile: RaspberryPi5.cmake
│
└── yocto-debug / yocto-release
    inherits: base-cross
    toolchainFile: Yocto.cmake
```

`jobs: 0` у `buildPresets` означає "використовувати всі доступні ядра".

---

## CMake модулі

### CompilerWarnings.cmake

```cmake
include(CompilerWarnings)
target_enable_warnings(my_target)           # Wall, Wextra, Wshadow, ...
target_enable_warnings(my_target STRICT)    # + Wlogical-op, Wuseless-cast, ...
target_enable_warnings(my_target PEDANTIC)  # STRICT + Wpedantic
```

Автоматично підбирає прапори для GCC, Clang або MSVC.

### Sanitizers.cmake

```cmake
include(Sanitizers)
target_enable_sanitizers(my_target ASAN UBSAN)
target_enable_sanitizers(my_target TSAN)     # TSAN несумісний з ASAN
```

При крос-компіляції — попереджає, але не блокує.
Глобальне вимкнення: `-DSANITIZERS_ENABLED=OFF`.

### CrossCompileHelpers.cmake

```cmake
include(CrossCompileHelpers)

# Додати прапор якщо компілятор підтримує
cross_check_cxx_flag(TARGET my_target FLAG -march=armv8.2-a)
cross_check_cxx_flag(TARGET my_target FLAG -fsomething REQUIRED)

# Перевірка фічі через try_compile (безпечно при крос-компіляції)
cross_feature_check(
    FEATURE CXX_HAS_INT128
    CODE "int main() { __int128 x = 0; (void)x; return 0; }"
)
if(HAVE_CXX_HAS_INT128)
    target_compile_definitions(my_target PRIVATE HAS_INT128=1)
endif()

# Діагностика конфігурації
cross_get_target_info()
```

### GitVersion.cmake

Отримання версії та хешу коміту з git під час конфігурації CMake.

```cmake
include(GitVersion)

# Версія з найближчого тегу (формат X.Y.Z або vX.Y.Z), інакше FALLBACK
git_get_version(PROJECT_VERSION FALLBACK "0.1.0")

# Скорочений хеш HEAD (за замовчуванням 7 символів)
git_get_commit_hash(GIT_HASH)
git_get_commit_hash(GIT_HASH_LONG LENGTH 12)

message(STATUS "Version: ${PROJECT_VERSION}  Commit: ${GIT_HASH}")

# Типове використання — вбудувати у бінарник через configure_file
configure_file(version.h.in version.h @ONLY)
```

Якщо `git` не знайдено або тег відсутній — повертається значення `FALLBACK`
(за замовчуванням `"0.0.0"`). Якщо HEAD недоступний — хеш повертається як
`"unknown"`.

### InstallHelpers.cmake

```cmake
include(InstallHelpers)  # підключається автоматично через BuildConfig.cmake

project_setup_install(opencv_example)
# → install_opencv_example          (bin/ + lib/ з EP залежностями)
# → install_opencv_example_stripped (той самий набір, зі strip-all/strip-debug)
#   [тільки для RelWithDebInfo]
```

Аналіз залежностей через `ep_check_binary_deps` відбувається у момент запуску цілі —
після збірки, а не під час конфігурації.

```bash
cmake --build build/rpi4-relwithdebinfo --target install_opencv_example
cmake --build build/rpi4-relwithdebinfo --target install_opencv_example_stripped
```

---

## Сторонні бібліотеки (cmake/external/)

### Режим inline (за замовчуванням)

Підключіть `ExternalDeps.cmake` з кореневого `CMakeLists.txt`:

```cmake
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/external/ExternalDeps.cmake")

# Далі можна лінкувати до зібраних imported targets:
target_link_libraries(my_app PRIVATE PNG::PNG JPEG::JPEG OpenSSL::SSL)
```

Кожна бібліотека підтримує два режими через опцію `USE_SYSTEM_<LIB>`:

| Опція | Значення за замовч. | Поведінка |
|---|---|---|
| `USE_SYSTEM_LIBPNG` | `OFF` | зібрати з джерел через ExternalProject |
| `USE_SYSTEM_LIBJPEG` | `OFF` | зібрати з джерел через ExternalProject |
| `USE_SYSTEM_LIBTIFF` | `OFF` | зібрати з джерел через ExternalProject |
| `USE_SYSTEM_OPENSSL` | `OFF` | зібрати з джерел через ExternalProject |
| `USE_SYSTEM_BOOST` | `OFF` | зібрати з джерел через ExternalProject |
| `USE_SYSTEM_OPENCV` | `OFF` | зібрати з джерел через ExternalProject |
| `USE_SYSTEM_LIBCAMERA` | `OFF` | зібрати з джерел через Meson ExternalProject |
| `USE_SYSTEM_LIBPISP` | `OFF` | зібрати з джерел через Meson ExternalProject |
| `USE_SYSTEM_RPICAMAPPS` | `OFF` | зібрати з джерел через Meson ExternalProject |
| `USE_SYSTEM_RPCLIB` | `OFF` | зібрати з джерел через ExternalProject |

```bash
# Використати системний OpenSSL замість збірки з джерел
cmake --preset rpi4-release -DUSE_SYSTEM_OPENSSL=ON -DRPI_SYSROOT=/srv/rpi4-sysroot
```

Бібліотеки встановлюються у `~/build/SupportRaspberryPI/external/<toolchain>/<BuildType>/`.
Кореневу директорію збірки можна змінити: `-DBUILD_ROOT=/mnt/nvme/proj`.

### Структура директорій збірки

```
~/build/                              ← BUILD_ROOT (за замовч.)
└── SupportRaspberryPI/
    ├── external_sources/             ← git-клони сорців (спільні для всіх toolchain)
    ├── external/                     ← скомпільовані бібліотеки (per-toolchain)
    │   ├── RaspberryPi4/Release/
    │   └── native/Debug/
    ├── rpi4-release/                 ← preset build dirs
    └── native-debug/
```

### Режим SuperBuild

SuperBuild будує всі залежності як окремі ExternalProject, потім основний
проєкт — теж як ExternalProject. Зручно для CI: deps кешуються між запусками.

```cmake
# CMakeLists.txt
if(SUPERBUILD)
    include(cmake/SuperBuild.cmake)
    return()
endif()
```

```bash
# Перша збірка (збирає deps + основний проєкт)
cmake -DSUPERBUILD=ON -B build-super --preset rpi4-release
cmake --build build-super

# Після зміни коду — тільки основний проєкт перебудовується
cmake --build build-super
```

### Порядок залежностей

```
LibPng  ──┐
LibJpeg ──┼──▶ LibTiff ──┐
          │               ├──▶ OpenCV
OpenSSL ──┘──────────────┘──▶ LibEvent ──▶ LibCamera ──┐
Boost   ─────────────────────────────────────────────┤
                                                       ├──▶ LibPisp
                                                       └──▶ RpiCamApps
Eigen3  ──┐
          ├──▶ AirSim
Rpclib  ──┘
PhySys  ──────▶ PhySysCpp
```

---

## Підключення до власного CMakeLists.txt

```cmake
# Додайте cmake/modules до шляху пошуку:
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules")

include(CompilerWarnings)
include(Sanitizers)
include(CrossCompileHelpers)
include(GitVersion)

git_get_version(PROJECT_VERSION)
git_get_commit_hash(GIT_HASH)

add_executable(my_app src/main.cpp)
target_enable_warnings(my_app STRICT)

if(ENABLE_ASAN)
    target_enable_sanitizers(my_app ASAN UBSAN)
endif()
```

Або вкажіть toolchain при конфігурації:
```bash
cmake -B build \
    -DCMAKE_TOOLCHAIN_FILE=<шлях>/cmake/toolchains/RaspberryPi4.cmake \
    -DCMAKE_MODULE_PATH=<шлях>/cmake/modules
```
