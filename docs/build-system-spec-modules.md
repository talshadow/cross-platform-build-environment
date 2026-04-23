# Специфікація: CMake модулі API

Всі модулі знаходяться у `cmake/modules/`.  
Підключення: `list(APPEND CMAKE_MODULE_PATH "<path>/cmake/modules")` + `include(<Module>)`.

---

## CompilerWarnings.cmake

### target_enable_warnings

```cmake
target_enable_warnings(<target> [NORMAL | STRICT | PEDANTIC])
```

Додає набір попереджень компілятора до `<target>` через `target_compile_options(PRIVATE ...)`.

#### Параметри

| Параметр | Тип | Обов'язковий | Опис |
|---|---|---|---|
| `target` | ім'я CMake цілі | так | ціль до якої застосовуються попередження |
| рівень | keyword | ні | `NORMAL` (за замовч.), `STRICT`, `PEDANTIC` |

#### Рівні попереджень

**NORMAL** (за замовчуванням) — базовий набір для GCC/Clang:
```
-Wall -Wextra -Wshadow -Wnon-virtual-dtor -Wcast-align
-Wunused -Woverloaded-virtual -Wconversion -Wsign-conversion
-Wdouble-promotion -Wformat=2 -Wimplicit-fallthrough
-Wnull-dereference
```

**STRICT** — NORMAL плюс:
```
-Wmisleading-indentation -Wduplicated-cond -Wduplicated-branches
-Wlogical-op -Wuseless-cast
```

**PEDANTIC** — STRICT плюс:
```
-Wpedantic
```

#### Поведінка за компілятором

| Компілятор | Набір |
|---|---|
| GCC | `_COMMON_WARNINGS` (відповідно до рівня) |
| Clang | `_COMMON_WARNINGS` + `-Wno-gnu-zero-variadic-macro-arguments` |
| MSVC | `/W4` + набір `/w14*` та `/we4*` (незалежно від рівня) |

#### Помилки та обмеження

- Не перевіряє чи підтримує компілятор кожен прапор — `GCC`/`Clang`-специфічні прапори (наприклад `-Wlogical-op`) ігноруються якщо компілятор їх не підтримує (GCC просто попередить).
- Прапори STRICT (`-Wlogical-op`, `-Wuseless-cast`) є **GCC-специфічними** і не підтримуються Clang — Clang їх проігнорує зі своїм попередженням.

#### Приклади

```cmake
include(CompilerWarnings)

target_enable_warnings(my_lib)            # NORMAL
target_enable_warnings(my_app STRICT)     # STRICT
target_enable_warnings(my_test PEDANTIC)  # PEDANTIC
```

---

## Sanitizers.cmake

### Глобальна опція

```cmake
option(SANITIZERS_ENABLED "Дозволити санітайзери" ON)
```

`-DSANITIZERS_ENABLED=OFF` вимикає всі санітайзери глобально. Викликати
`target_enable_sanitizers()` стає no-op.

---

### target_enable_sanitizers

```cmake
target_enable_sanitizers(<target> [ASAN] [UBSAN] [TSAN] [LSAN])
```

Додає прапори санітайзерів до `<target>` через
`target_compile_options(PRIVATE ...)` та `target_link_options(PRIVATE ...)`.
Також додає `-g` для читабельних stack traces.

#### Параметри

| Параметр | Тип | Обов'язковий | Опис |
|---|---|---|---|
| `target` | ім'я CMake цілі | так | ціль до якої застосовуються санітайзери |
| `ASAN` | keyword | ні | AddressSanitizer |
| `UBSAN` | keyword | ні | UndefinedBehaviorSanitizer |
| `TSAN` | keyword | ні | ThreadSanitizer |
| `LSAN` | keyword | ні | LeakSanitizer (окремо, якщо без ASAN) |

#### Прапори за санітайзером

| Санітайзер | Compile flags | Link flags |
|---|---|---|
| `ASAN` | `-fsanitize=address -fno-omit-frame-pointer` | `-fsanitize=address` |
| `UBSAN` | `-fsanitize=undefined -fsanitize=float-divide-by-zero -fsanitize=integer-divide-by-zero -fno-sanitize-recover=undefined` | `-fsanitize=undefined` |
| `TSAN` | `-fsanitize=thread -fno-omit-frame-pointer` | `-fsanitize=thread` |
| `LSAN` (без ASAN) | `-fsanitize=leak` | `-fsanitize=leak` |

LSAN вбудований в ASAN — окремий `-fsanitize=leak` застосовується лише якщо ASAN не увімкнений.

#### Помилки

| Умова | Поведінка |
|---|---|
| `TSAN` + (`ASAN` або `LSAN`) | `FATAL_ERROR`: несумісні санітайзери |
| Невідомий keyword | `WARNING` з іменем невідомого санітайзера |
| `MSVC` | `WARNING` + тільки `/fsanitize=address`, повертається |
| Крос-компіляція | `WARNING` (може не запуститись без runtime), продовжує |
| `SANITIZERS_ENABLED=OFF` | no-op |

#### Приклади

```cmake
include(Sanitizers)

# ASAN + UBSAN (типовий розробницький пресет)
target_enable_sanitizers(my_app ASAN UBSAN)

# Thread sanitizer (окремий build — несумісний з ASAN)
target_enable_sanitizers(my_app TSAN)

# Тільки Leak Sanitizer
target_enable_sanitizers(my_app LSAN)

# Вимкнути глобально
cmake ... -DSANITIZERS_ENABLED=OFF
```

---

## CrossCompileHelpers.cmake

### cross_check_cxx_flag

```cmake
cross_check_cxx_flag(TARGET <target> FLAG <flag> [REQUIRED])
```

Перевіряє підтримку C++ прапора компілятором через `check_cxx_compiler_flag()`.
При успіху додає прапор через `target_compile_options(PRIVATE ...)`.

#### Параметри

| Параметр | Тип | Обов'язковий | Опис |
|---|---|---|---|
| `TARGET` | keyword + значення | так | CMake ціль |
| `FLAG` | keyword + значення | так | прапор для перевірки (напр. `-march=armv8.2-a`) |
| `REQUIRED` | keyword | ні | якщо задано і прапор не підтримується — `FATAL_ERROR` |

#### Кешування

Результат перевірки кешується у змінній `HAVE_CXX_FLAG_<normalized_flag>`,
де `<normalized_flag>` — прапор з заміною всіх `[^a-zA-Z0-9_]` на `_`.

Приклад: `-march=armv8.2-a` → `HAVE_CXX_FLAG__march_armv8_2_a`.

#### Поведінка

| Стан | `REQUIRED` | Результат |
|---|---|---|
| Прапор підтримується | — | додається до target |
| Прапор не підтримується | ні | `STATUS` повідомлення, пропуск |
| Прапор не підтримується | так | `FATAL_ERROR` |
| `TARGET` або `FLAG` відсутні | — | `FATAL_ERROR` |

#### Приклади

```cmake
include(CrossCompileHelpers)

cross_check_cxx_flag(TARGET my_app FLAG -march=armv8.2-a)
cross_check_cxx_flag(TARGET my_app FLAG -fsomething REQUIRED)
```

---

### cross_feature_check

```cmake
cross_feature_check(
    FEATURE  <name>
    CODE     <cpp_code>
    [COMPILE_FLAGS <flags...>]
)
```

Перевіряє наявність C++ фічі через `try_compile`. Ніколи не використовує
`try_run` — безпечно при крос-компіляції.

#### Параметри

| Параметр | Тип | Обов'язковий | Опис |
|---|---|---|---|
| `FEATURE` | keyword + значення | так | ім'я для кешованої змінної `HAVE_<FEATURE>` |
| `CODE` | keyword + значення | так | повний C++ код для компіляції (включно з `main`) |
| `COMPILE_FLAGS` | keyword + список | ні | додаткові прапори для `try_compile` |

#### Кешування

Результат зберігається у `CACHE BOOL HAVE_<FEATURE>`. При повторному виклику
з тим самим `FEATURE` — одразу повертається (no-op).

#### Результат

Після виклику доступна змінна `HAVE_<FEATURE>`:
- `TRUE` — код скомпілювався успішно.
- `FALSE` — компіляція провалилась.

#### Поведінка

| Стан | Результат |
|---|---|
| `FEATURE` або `CODE` відсутні | `FATAL_ERROR` |
| `HAVE_<FEATURE>` вже визначена | no-op (повертається одразу) |
| Компіляція успішна | `HAVE_<FEATURE> = TRUE`, `STATUS` повідомлення |
| Компіляція провалена | `HAVE_<FEATURE> = FALSE`, `STATUS` повідомлення |

#### Приклад

```cmake
include(CrossCompileHelpers)

cross_feature_check(
    FEATURE CXX_HAS_INT128
    CODE    "int main() { __int128 x = 0; (void)x; return 0; }"
)
if(HAVE_CXX_HAS_INT128)
    target_compile_definitions(my_app PRIVATE HAS_INT128=1)
endif()
```

---

### cross_get_target_info

```cmake
cross_get_target_info()
```

Виводить діагностичну інформацію про поточну конфігурацію.

Параметрів немає. Виводить через `message(STATUS ...)`:

```
=== Cross-compile configuration ===
  CMAKE_CROSSCOMPILING     : TRUE/FALSE
  CMAKE_SYSTEM_NAME        : Linux
  CMAKE_SYSTEM_PROCESSOR   : aarch64
  CMAKE_C_COMPILER         : /usr/bin/aarch64-linux-gnu-gcc
  CMAKE_CXX_COMPILER       : /usr/bin/aarch64-linux-gnu-g++
  CMAKE_SYSROOT            : /srv/rpi4-sysroot
  CMAKE_FIND_ROOT_PATH     : /srv/rpi4-sysroot
===================================
```

---

## GitVersion.cmake

### git_get_version

```cmake
git_get_version(<out_var> [FALLBACK <version>])
```

Отримує версію проєкту з найближчого git тегу у форматі `X.Y.Z` або `vX.Y.Z`.

#### Параметри

| Параметр | Тип | Обов'язковий | Опис |
|---|---|---|---|
| `out_var` | змінна | так | куди записується результат |
| `FALLBACK` | keyword + значення | ні | версія при відсутності тегу або git (за замовч. `"0.0.0"`) |

#### Алгоритм пошуку тегу

1. `git describe --tags --match "[0-9]*.[0-9]*.[0-9]*" --abbrev=0`
2. Якщо не знайдено: `git describe --tags --match "v[0-9]*.[0-9]*.[0-9]*" --abbrev=0`
3. Відкидає префікс `v` / `V`.
4. Перевіряє формат `^[0-9]+\.[0-9]+\.[0-9]+$`.

#### Поведінка

| Умова | Результат |
|---|---|
| Тег знайдений, формат вірний | `out_var = "X.Y.Z"` |
| git не знайдено | `WARNING`, `out_var = FALLBACK` |
| Тег не знайдено | `WARNING`, `out_var = FALLBACK` |
| Тег не відповідає формату | `WARNING`, `out_var = FALLBACK` |

#### Приклади

```cmake
include(GitVersion)

git_get_version(MY_VERSION)                  # → "1.2.3" або "0.0.0"
git_get_version(MY_VERSION FALLBACK "1.0.0") # → "1.2.3" або "1.0.0"

project(MyApp VERSION ${MY_VERSION})
```

---

### git_get_commit_hash

```cmake
git_get_commit_hash(<out_var> [LENGTH <n>])
```

Отримує скорочений хеш останнього коміту (`git rev-parse --short=<n> HEAD`).

#### Параметри

| Параметр | Тип | Обов'язковий | Опис |
|---|---|---|---|
| `out_var` | змінна | так | куди записується результат |
| `LENGTH` | keyword + число | ні | кількість символів хешу (за замовч. `7`) |

#### Поведінка

| Умова | Результат |
|---|---|
| Успіх | `out_var = "<hash>"` (рядок з `LENGTH` символів) |
| git не знайдено | `WARNING`, `out_var = "unknown"` |
| HEAD недоступний (порожній репозиторій) | `WARNING`, `out_var = "unknown"` |

#### Приклади

```cmake
include(GitVersion)

git_get_commit_hash(GIT_HASH)               # → "a1b2c3d" (7 символів)
git_get_commit_hash(GIT_HASH_LONG LENGTH 12) # → "a1b2c3d4e5f6"

# Вбудувати у бінарник
configure_file(version.h.in version.h @ONLY)
# version.h.in: #define GIT_COMMIT "@GIT_HASH@"
```

---

## BinaryDeps.cmake

### ep_check_binary_deps

```cmake
ep_check_binary_deps(<binary_path> [<out_var>])
```

Рекурсивно знаходить усі динамічні залежності бінарного файлу та класифікує
їх за джерелом. Виводить дерево залежностей у лог CMake (`message(STATUS ...)`).

#### Параметри

| Параметр | Тип | Обов'язковий | Опис |
|---|---|---|---|
| `binary_path` | шлях | так | шлях до бінарника або `.so` |
| `out_var` | змінна | ні | якщо вказано — записує повні шляхи EP бібліотек для деплою (без TOOLCHAIN при крос-збірці, без MISSING, без дублів) |

#### Категорії залежностей

| Мітка | Джерело | Рекурсія |
|---|---|---|
| `[EP]` | `EXTERNAL_INSTALL_PREFIX/lib` | так |
| `[TOOLCHAIN]` | директорія компілятора (`gcc -print-libgcc-file-name`) | тільки без sysroot |
| `[SYSROOT]` | `CMAKE_SYSROOT/lib`, `/usr/lib` + multiarch | ні (листовий вузол) |
| `[SYSTEM]` | `/lib`, `/usr/lib`, `/lib64`, `/usr/lib64` + multiarch | ні (листовий вузол) |
| `[MISSING]` | не знайдено жодним шляхом | — |

> **Крос-збірка (`CMAKE_SYSROOT` задано):** бібліотеки категорії `[TOOLCHAIN]` (libstdc++,
> libgcc_s тощо) **не включаються** у deploy list і рекурсія по них не відбувається —
> вони вже присутні на цільовій платформі в правильній версії.

#### Зовнішні залежності

| Змінна | Звідки | Призначення |
|---|---|---|
| `CMAKE_READELF` | CMake (крос-білд) або `find_program(readelf)` | читання ELF dynamic section |
| `EXTERNAL_INSTALL_PREFIX` | `cmake/external/Common.cmake` | директорія EP артефактів |
| `CMAKE_SYSROOT` | toolchain файл (опційно) | sysroot для крос-компіляції |
| `CMAKE_C_COMPILER` | toolchain / системний | пошук директорії тулчейна |

#### Поведінка

| Стан | Результат |
|---|---|
| `binary_path` не існує | `WARNING`, повернення |
| `readelf` не знайдено | `FATAL_ERROR` |
| Цикл залежностей | захист через список відвіданих вузлів |
| `out_var` не переданий | результат тільки у логу |
| `out_var` переданий | список повних шляхів у PARENT_SCOPE |

#### Вивід

Дерево з відступами (2 пробіли на рівень) + зведення:

```
-- [BinaryDeps] /path/to/libopencv_core.so
-- [BinaryDeps] ─────────────────────────────────────────
--   [EP]        libjpeg.so.62  (/opt/ep/lib/libjpeg.so.62)
--     [EP]        libz.so.1  (/opt/ep/lib/libz.so.1)
--   [TOOLCHAIN] libstdc++.so.6  (/usr/lib/gcc/.../libstdc++.so.6)
--   [SYSROOT]   libc.so.6  (/srv/sysroot/lib/aarch64-linux-gnu/libc.so.6)
--   [SYSTEM]    libm.so.6  (/usr/lib/x86_64-linux-gnu/libm.so.6)
-- [BinaryDeps] ─────────────────────────────────────────
-- [BinaryDeps] Зведення:
-- [BinaryDeps]   [EP]        5 бібліотек(и)
-- [BinaryDeps]   [TOOLCHAIN] 2 бібліотек(и)
-- [BinaryDeps]   [SYSROOT]   8 бібліотек(и)
-- [BinaryDeps]   [SYSTEM]    3 бібліотек(и)
```

#### Приклади

```cmake
include(BinaryDeps)

# Тільки вивід у лог
ep_check_binary_deps("/path/to/mybinary")

# Отримати список повних шляхів
ep_check_binary_deps("/path/to/mybinary" MY_DEPS)
foreach(_lib IN LISTS MY_DEPS)
    message(STATUS "  dep: ${_lib}")
endforeach()

# З generator expression (у post-build кроці)
ep_check_binary_deps($<TARGET_FILE:my_target> MY_TARGET_DEPS)

# Скопіювати всі EP залежності поряд з бінарником
ep_check_binary_deps("${_mylib}" _deps)
foreach(_dep IN LISTS _deps)
    if(_dep MATCHES "^${EXTERNAL_INSTALL_PREFIX}")
        file(COPY "${_dep}" DESTINATION "${CMAKE_INSTALL_PREFIX}/lib")
    endif()
endforeach()
```

---

## InstallHelpers.cmake

### project_setup_install

```cmake
project_setup_install(<target>)
```

Налаштовує кастомну інсталяцію головного виконуваного файлу.
Підключається автоматично через `cmake/BuildConfig.cmake`.

#### Параметри

| Параметр | Тип | Обов'язковий | Опис |
|---|---|---|---|
| `target` | ім'я CMake цілі | так | ціль для інсталяції |

#### Цілі що створюються

| Ціль | Умова | Призначення |
|---|---|---|
| `install_<target>` | завжди | Копіює виконуваний файл і EP залежності |
| `install_<target>_stripped` | тільки `RelWithDebInfo` | Те саме + strip debug-інформації |

#### Структура директорій інсталяції

```
${CMAKE_BINARY_DIR}/
├── install_<BuildType>/
│   ├── bin/    — виконуваний файл
│   └── lib/    — EP залежності (з symlink-chain)
│
└── install_RelWithDebInfo_stripped/    ← тільки для RelWithDebInfo
    ├── bin/    — виконуваний файл (--strip-all)
    └── lib/    — залежності (--strip-debug, симлінки пропускаються)
```

#### Реалізація

Обидві цілі запускають `cmake/install_project.cmake` через `add_custom_target` з
`cmake -P`. Аналіз залежностей виконується через `ep_check_binary_deps` (BinaryDeps.cmake)
у момент запуску цілі — після збірки, а не під час конфігурації.

При стрипуванні:
- `--strip-all` для виконуваного файлу (видаляє всі символи та налагоджувальну інформацію)
- `--strip-debug` для кожної `.so` (зберігає таблицю символів для `dlopen`)
- Симлінки пропускаються

#### Зовнішні залежності

| Змінна | Звідки | Призначення |
|---|---|---|
| `EXTERNAL_INSTALL_PREFIX` | `cmake/external/Common.cmake` | пошук EP бібліотек |
| `CMAKE_READELF` | toolchain або `find_program(readelf)` | аналіз ELF залежностей |
| `CMAKE_STRIP` | toolchain або системний | стрипування |
| `CMAKE_SYSROOT` | toolchain файл | класифікація sysroot бібліотек |
| `CMAKE_INSTALL_BINDIR` / `LIBDIR` | `GNUInstallDirs` | відносні шляхи (bin/, lib/) |

#### Помилки

| Умова | Поведінка |
|---|---|
| `target` не існує | `FATAL_ERROR` |
| `cmake/install_project.cmake` не знайдено | `FATAL_ERROR` |
| `DO_STRIP=ON` + `CMAKE_STRIP` не передано | `WARNING`, стрипування пропускається |

#### Приклади

```cmake
add_executable(opencv_example main.cpp)
target_link_libraries(opencv_example PRIVATE OpenCV::opencv_core ...)
ep_target_add_compile_deps(opencv_example)
project_setup_install(opencv_example)
# → install_opencv_example, install_opencv_example_stripped (RelWithDebInfo)
```

```bash
# Зібрати і встановити
cmake --build build/rpi4-relwithdebinfo --target opencv_example
cmake --build build/rpi4-relwithdebinfo --target install_opencv_example

# Стрипована версія для деплою
cmake --build build/rpi4-relwithdebinfo --target install_opencv_example_stripped
```

---

## Сумісність між модулями

| Комбінація | Статус |
|---|---|
| `CompilerWarnings` + `Sanitizers` | сумісні |
| `Sanitizers(ASAN)` + `Sanitizers(TSAN)` на одному target | **FATAL_ERROR** |
| `Sanitizers` при `CMAKE_CROSSCOMPILING=TRUE` | `WARNING`, продовжує |
| `cross_check_cxx_flag` + `target_enable_warnings` | сумісні, незалежні |
| `GitVersion` при відсутньому git | `WARNING`, повертає fallback/unknown |
| `BinaryDeps` при відсутньому `readelf` | `FATAL_ERROR` |
| `InstallHelpers` + `BinaryDeps` | сумісні (InstallHelpers викликає BinaryDeps внутрішньо) |
