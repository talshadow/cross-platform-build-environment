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
│   binaryDir: ${sourceDir}/build/${presetName}
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
| `platform` | `native`, `ubuntu2004`, `ubuntu2404`, `clang`, `clang<ver>`, `rpi4`, `rpi5`, `yocto` |
| `buildtype` | `debug`, `release`, `relwithdebinfo` |
| `variant` | `asan`, `tsan`, (майбутні: `lto`, `coverage`) |

**Приклади:** `rpi4-release`, `ubuntu2404-debug`, `ubuntu2404-asan`, `clang-tsan`, `clang18-release`.

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

## Змінні, зарезервовані базовими пресетами

| Змінна | Задана в | Значення |
|---|---|---|
| `CMAKE_EXPORT_COMPILE_COMMANDS` | `base` | `ON` |
| `BUILD_TESTS` | `base-cross` | `OFF` |
| `binaryDir` | `base` | `${sourceDir}/build/${presetName}` |
| `generator` | `base` | `Ninja` |

Не перевизначати ці змінні в конкретних пресетах без вагомої причини.
