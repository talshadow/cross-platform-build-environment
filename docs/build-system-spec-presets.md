# Специфікація: CMakePresets.json

## Версія формату

```json
{
  "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 23, "patch": 0 }
}
```

Мінімальна версія CMake — **3.23** (підтримка `version: 6`).

---

## Ієрархія наслідування

```
base  (hidden)
│   generator: Ninja
│   binaryDir: $env{HOME}/build/${sourceDirName}/${presetName}
│   CMAKE_EXPORT_COMPILE_COMMANDS: ON
│
└── base-cross  (hidden)
│   inherits: base
│   BUILD_TESTS: OFF          ← тести вимкнені для крос-пресетів
│
├── <native-preset>           ← успадковує base
└── <cross-preset>            ← успадковує base-cross
```

**Правило:** нативні пресети успадковують `base`; крос-пресети — `base-cross`.

---

## Конвенція іменування

```
<platform>-<buildtype>[-variant]
```

| Частина | Допустимі значення |
|---|---|
| `platform` | `native`, `clang`, `clang<ver>`, `rpi4`, `rpi5`, `yocto` |
| `buildtype` | `debug`, `release`, `relwithdebinfo` |
| `variant` | `asan`, `tsan`, (майбутні: `lto`, `coverage`) |

**Приклади:** `rpi4-release`, `native-debug`, `native-asan`, `clang-tsan`, `clang-release`.

`clang<ver>` — версійний Clang (напр. `clang18`); `clang` без версії — системний.

Назва `configurePreset` у `buildPresets` і `testPresets` **повинна точно збігатись** з назвою відповідного `configurePreset`.

---

## Обов'язкові поля — configurePreset

| Поле | Обов'язкове | Значення |
|---|---|---|
| `name` | так | унікальне ім'я |
| `inherits` | так | `"base"` або `"base-cross"` (або похідний від них) |
| `toolchainFile` | так | `"${sourceDir}/cmake/toolchains/<File>.cmake"` |
| `cacheVariables.CMAKE_BUILD_TYPE` | так | `"Debug"` або `"Release"` |
| `displayName` | рекомендовано | коротка назва для IDE |
| `description` | рекомендовано | опис для `cmake --list-presets` |

`hidden: true` — лише для базових пресетів (`base`, `base-cross`).

---

## Обов'язкові поля — buildPreset

```json
{ "name": "<same-as-configure>", "configurePreset": "<name>", "jobs": 0 }
```

- `jobs: 0` означає "всі доступні ядра" (`-j$(nproc)`).
- Кожен `configurePreset` повинен мати відповідний `buildPreset` з тим самим ім'ям.

---

## Обов'язкові поля — testPreset

```json
{
  "name": "<same-as-configure>",
  "configurePreset": "<name>",
  "output": { "outputOnFailure": true },
  "execution": { "jobs": <n> }
}
```

- `testPreset` створюється **лише для нативних** пресетів (`ubuntu*`, `clang*`, `native`).
- `jobs: 1` — для санітайзерів (ASAN/TSAN), щоб уникнути перехресного ��уму.
- `jobs: 4` — для звичайних нативних пресетів.
- `relwithdebinfo` пресети зазвичай не мають testPreset.

---

## Правила cacheVariables

### Нативний Release
```json
"ENABLE_LTO": "ON"
```
LTO вмикається лише в Release нативних пресетів (не крос — ризик несумісності lto плагінів).

### Санітайзерний пресет
Успадковує відповідний `debug` пресет і додає:
```json
"ENABLE_ASAN": "ON",
"ENABLE_UBSAN": "ON"
```
або (окремо, несумісний з ASAN):
```json
"ENABLE_TSAN": "ON"
```

### Крос-пресети
`BUILD_TESTS: OFF` успадковується з `base-cross` — не треба повторювати.

---

## Додавання нового пресету — чеклист

1. Додати `configurePreset` з `name`, `inherits`, `toolchainFile`, `CMAKE_BUILD_TYPE`.
2. Додати `buildPreset` з тим самим `name`.
3. Якщо нативний — додати `testPreset`.
4. Якщо нативний Release — додати `"ENABLE_LTO": "ON"`.
5. Перевірити: `cmake --list-presets` показує новий пресет.
6. Перевірити: `cmake --preset <name>` конфігурується без помилок.

---

## Користувацькі пресети (CMakeUserPresets.json)

Для локальних налаштувань (шляхи sysroot, кастомні toolchain, специфічні змінні)
використовуйте `CMakeUserPresets.json` — він не комітиться в git (вже у `.gitignore`).

### Структура файлу

```json
{
  "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 28, "patch": 0 },
  "configurePresets": [...],
  "buildPresets": [...],
  "testPresets": [...]
}
```

---

### Приклад 1: RPi 4 зі зафіксованим sysroot

Найчастіший кейс — зафіксувати `RPI_SYSROOT` щоб не передавати його щоразу.

```json
{
  "version": 6,
  "configurePresets": [
    {
      "name": "my-rpi4-release",
      "displayName": "My RPi4 — Release (home sysroot)",
      "inherits": "rpi4-release",
      "cacheVariables": {
        "RPI_SYSROOT": "/srv/rpi4-sysroot"
      }
    }
  ],
  "buildPresets": [
    { "name": "my-rpi4-release", "configurePreset": "my-rpi4-release", "jobs": 0 }
  ]
}
```

```bash
cmake --preset my-rpi4-release   # RPI_SYSROOT вже вшитий
cmake --build --preset my-rpi4-release
```

---

### Приклад 2: CT-NG toolchain з кастомним префіксом

CT-NG створює компілятор з нестандартним triple (напр. `aarch64-unknown-linux-gnu`
замість `aarch64-linux-gnu`). Передаємо `RPI4_TOOLCHAIN_PREFIX` разом із `RPI_SYSROOT`.

```json
{
  "version": 6,
  "configurePresets": [
    {
      "name": "my-rpi4-ctng",
      "displayName": "My RPi4 — CT-NG toolchain",
      "inherits": "rpi4-release",
      "cacheVariables": {
        "RPI_SYSROOT":          "/srv/rpi4-sysroot",
        "RPI4_TOOLCHAIN_PREFIX": "aarch64-unknown-linux-gnu",
        "RPI4_GCC_VERSION":      "14"
      }
    }
  ],
  "buildPresets": [
    { "name": "my-rpi4-ctng", "configurePreset": "my-rpi4-ctng", "jobs": 0 }
  ]
}
```

---

### Приклад 3: Кілька пресетів для різних конфігурацій

```json
{
  "version": 6,
  "configurePresets": [
    {
      "name": "my-rpi4-debug",
      "displayName": "My RPi4 — Debug",
      "inherits": "rpi4-debug",
      "cacheVariables": {
        "RPI_SYSROOT": "/srv/rpi4-sysroot"
      }
    },
    {
      "name": "my-rpi4-release",
      "displayName": "My RPi4 — Release",
      "inherits": "rpi4-release",
      "cacheVariables": {
        "RPI_SYSROOT": "/srv/rpi4-sysroot"
      }
    },
    {
      "name": "my-rpi5-release",
      "displayName": "My RPi5 — Release",
      "inherits": "rpi5-release",
      "cacheVariables": {
        "RPI_SYSROOT": "/srv/rpi5-sysroot"
      }
    }
  ],
  "buildPresets": [
    { "name": "my-rpi4-debug",   "configurePreset": "my-rpi4-debug",   "jobs": 0 },
    { "name": "my-rpi4-release", "configurePreset": "my-rpi4-release", "jobs": 0 },
    { "name": "my-rpi5-release", "configurePreset": "my-rpi5-release", "jobs": 0 }
  ]
}
```

---

### Приклад 4: Зовнішні бібліотеки з системи замість збірки

```json
{
  "version": 6,
  "configurePresets": [
    {
      "name": "my-native-system-libs",
      "displayName": "Native — Debug, системні бібліотеки",
      "inherits": "native-debug",
      "cacheVariables": {
        "USE_SYSTEM_OPENSSL": "ON",
        "USE_SYSTEM_BOOST":   "ON",
        "USE_SYSTEM_OPENCV":  "ON"
      }
    }
  ],
  "buildPresets": [
    { "name": "my-native-system-libs", "configurePreset": "my-native-system-libs", "jobs": 0 }
  ]
}
```

---

### Приклад 5: Змінна через середовище (environment)

Якщо sysroot визначається динамічно або знаходиться в змінній середовища,
використовуйте `environment` і `$env{...}` замість жорсткого шляху.

```json
{
  "version": 6,
  "configurePresets": [
    {
      "name": "my-rpi4-env",
      "displayName": "My RPi4 — sysroot з $RPI4_SYSROOT",
      "inherits": "rpi4-release",
      "environment": {
        "RPI4_SYSROOT": "/srv/rpi4-sysroot"
      },
      "cacheVariables": {
        "RPI_SYSROOT": "$env{RPI4_SYSROOT}"
      }
    }
  ],
  "buildPresets": [
    { "name": "my-rpi4-env", "configurePreset": "my-rpi4-env", "jobs": 0 }
  ]
}
```

```bash
RPI4_SYSROOT=/mnt/sysroots/rpi4 cmake --preset my-rpi4-env
```

---

### Правила для CMakeUserPresets.json

- **Не комітити** — вже у `.gitignore`. Файл містить шляхи, специфічні для вашого ПК.
- **Назви пресетів** — рекомендовано з префіксом (напр. `my-`, `dev-`, `local-`)
  щоб уникнути конфлікту з іменами у `CMakePresets.json`.
- **`inherits`** — завжди успадковувати від існуючого пресету з `CMakePresets.json`,
  а не дублювати `toolchainFile`, `binaryDir` тощо.
- **`buildPreset.name`** — має точно збігатись з `configurePreset.name`.
- **`jobs: 0`** у buildPreset — використовує всі ядра (`-j$(nproc)`).
- **Версія формату** — `"version": 6` та `cmakeMinimumRequired 3.28`.

---

## Змінні, зарезервовані базовими пресетами

| Змінна | Задана в | Значення |
|---|---|---|
| `CMAKE_EXPORT_COMPILE_COMMANDS` | `base` | `ON` |
| `BUILD_TESTS` | `base-cross` | `OFF` |
| `binaryDir` | `base` | `$env{HOME}/build/${sourceDirName}/${presetName}` |
| `generator` | `base` | `Ninja` |

Не перевизначати ці змінні в конкретних пресетах без вагомої причини.
