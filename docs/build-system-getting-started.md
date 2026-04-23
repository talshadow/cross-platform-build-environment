# Швидкий старт

## Підтримувані host-системи

| ОС | Версія | Пакетний менеджер |
|---|---|---|
| Ubuntu | 20.04 LTS | apt |
| Ubuntu | 24.04 LTS | apt |
| Arch Linux | rolling | pacman + AUR (yay/paru) |
| CachyOS | rolling | pacman + AUR (yay/paru) |

> На Arch/CachyOS для ARM 32-bit крос-компілятора (`arm-linux-gnueabihf`) потрібен AUR-хелпер
> (`yay` або `paru`). Для AArch64 (`aarch64-linux-gnu`) достатньо офіційних репозиторіїв.

---

## 1. Встановлення крос-компіляторів

```bash
sudo ./scripts/build-system-install-toolchains.sh all
```

Скрипт автоматично визначає ОС і використовує `apt` (Ubuntu) або `pacman` (Arch/CachyOS).

Для вибіркового встановлення:
```bash
sudo ./scripts/build-system-install-toolchains.sh rpi-arm64 ninja cmake
```

Доступні варіанти: `all`, `rpi-arm32`, `rpi-arm64`, `native20`, `native24`, `native-arch`, `ninja`, `cmake`.

> **Arch/CachyOS — відмінності від Ubuntu:**
> - `aarch64-linux-gnu-gcc` встановлюється без версії (не `gcc-12`/`gcc-13`).
>   CMake toolchain автоматично переключається на неверсований компілятор.
> - `arm-linux-gnueabihf-gcc` доступний тільки через AUR. Потрібен `yay` або `paru`.
> - CMake 3.20+ та Ninja вже доступні в офіційних репозиторіях (`extra`).
> - `native-arch` замість `native20`/`native24` — встановлює системний GCC.

---

## 2. Отримання sysroot (необов'язково, але рекомендовано)

Без sysroot — збірка можлива, але лінкування проти бібліотек цільової системи
(OpenSSL, зв'язана з RPi, тощо) буде недоступне.

### Варіант A: через Docker (найпростіший, без фізичного RPi)

```bash
# RPi 3 / 4 / 5 (AArch64)
./scripts/build-system-get-sysroot-rpi.sh --method docker --arch arm64 --dest /srv/rpi4-sysroot

# RPi 2 / 3 (32-bit)
./scripts/build-system-get-sysroot-rpi.sh --method docker --arch arm/v7 --dest /srv/rpi2-sysroot
```

### Варіант B: з образу Raspberry Pi OS (.img)

```bash
# Завантажте образ з https://www.raspberrypi.com/software/operating-systems/
# Наприклад: 2024-07-04-raspios-bookworm-arm64-lite.img.xz

sudo ./scripts/build-system-get-sysroot-rpi.sh \
    --method image \
    --image 2024-07-04-raspios-bookworm-arm64-lite.img.xz \
    --dest /srv/rpi4-sysroot
```

> Потрібен root (`sudo`) для монтування образу через losetup.

### Варіант C: з живого Raspberry Pi

```bash
./scripts/build-system-get-sysroot-rpi.sh \
    --method live \
    --host 192.168.1.100 \
    --user pi \
    --dest /srv/rpi4-sysroot
```

### Отримання sysroot для Yocto

```bash
# 1. Встановити SDK (.sh інсталятор із Yocto build або з сервера)
./scripts/build-system-get-sysroot-yocto.sh --method sdk --installer ./poky-glibc-*.sh

# 2. Активувати SDK перед збіркою
source /opt/poky/<version>/environment-setup-<target>-poky-linux

# 3. Перевірити що SDK активоване
./scripts/build-system-get-sysroot-yocto.sh --method check
```

---

## 3. Збірка

### Через CMake presets (рекомендовано)

```bash
# Список доступних пресетів
cmake --list-presets

# Конфігурація + збірка (нативна, Debug)
cmake --preset native-debug
cmake --build --preset native-debug

# Крос-компіляція для RPi 4 без sysroot
cmake --preset rpi4-release
cmake --build --preset rpi4-release

# Крос-компіляція для RPi 4 зі sysroot
cmake --preset rpi4-release -DRPI_SYSROOT=/srv/rpi4-sysroot
cmake --build --preset rpi4-release
```

### Через скрипт build-system-build.sh

```bash
./scripts/build-system-build.sh rpi4-release
./scripts/build-system-build.sh rpi4-release -DRPI_SYSROOT=/srv/rpi4-sysroot
./scripts/build-system-build.sh native-asan
```

### Через cmake напряму (без presets)

```bash
cmake -B build/rpi4 \
    -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/RaspberryPi4.cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DRPI_SYSROOT=/srv/rpi4-sysroot
cmake --build build/rpi4 -j$(nproc)
```

### Інсталяція артефактів

Після збірки можна запустити кастомну ціль інсталяції яка збирає виконуваний файл
і всі EP залежності в єдину директорію (готово до розгортання на RPi):

```bash
# Зібрати виконуваний файл
cmake --build build/rpi4-relwithdebinfo

# Встановити в build/rpi4-relwithdebinfo/install_RelWithDebInfo/
cmake --build build/rpi4-relwithdebinfo --target install_opencv_example

# Стрипована версія (зменшений розмір, без налагоджувальних символів)
cmake --build build/rpi4-relwithdebinfo --target install_opencv_example_stripped
```

Результат:
```
build/rpi4-relwithdebinfo/install_RelWithDebInfo/
├── bin/opencv_example
└── lib/
    ├── libopencv_core.so → libopencv_core.so.4.10
    ├── libopencv_core.so.4.10 → libopencv_core.so.4.10.0
    ├── libopencv_core.so.4.10.0
    └── ...
```

Ціль `install_<target>_stripped` доступна **тільки** для пресетів з `RelWithDebInfo`.

---

## 4. Сторонні бібліотеки

За замовчуванням бібліотеки (libpng, libjpeg, OpenSSL, Boost, OpenCV тощо)
збираються з джерел через CMake ExternalProject і встановлюються у
`build/External/<toolchain>/<BuildType>/`.

### Підключення у CMakeLists.txt

```cmake
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/external/ExternalDeps.cmake")

target_link_libraries(my_app PRIVATE PNG::PNG JPEG::JPEG OpenSSL::SSL)
```

### Використати системну бібліотеку замість збірки

```bash
cmake --preset rpi4-release \
    -DRPI_SYSROOT=/srv/rpi4-sysroot \
    -DUSE_SYSTEM_OPENSSL=ON
```

### SuperBuild (рекомендовано для CI)

```bash
# Активувати SuperBuild — deps та основний проєкт як окремі EP
cmake -DSUPERBUILD=ON --preset rpi4-release -DRPI_SYSROOT=/srv/rpi4-sysroot
cmake --build build/rpi4-release
```

---

## 5. Тести

Тести запускаються лише для нативних пресетів (`native-*`, `clang-*`).

```bash
# Всі тести
ctest --preset native-debug

# Один тест за ім'ям
ctest --preset native-debug -R my_test_name

# З виводом при помилці
ctest --preset native-debug --output-on-failure
```

---

## 6. Розгортання на RPi

```bash
# Зібрати
./scripts/build-system-build.sh rpi4-release -DRPI_SYSROOT=/srv/rpi4-sysroot

# Розгорнути
./scripts/build-system-deploy.sh \
    --preset rpi4-release \
    --host 192.168.1.100 \
    --user pi \
    --remote-dir /home/pi/my_app

# Розгорнути та одразу запустити
./scripts/build-system-deploy.sh \
    --preset rpi4-release \
    --host 192.168.1.100 \
    --run my_app \
    --run-args "--config /etc/app.cfg"
```

---

## Швидкий сценарій: RPi 4, з нуля до запуску

```bash
# 1. Встановити інструменти (Ubuntu або Arch/CachyOS — скрипт визначає ОС автоматично)
sudo ./scripts/build-system-install-toolchains.sh rpi-arm64 ninja cmake

# 2. Отримати sysroot (через Docker)
./scripts/build-system-get-sysroot-rpi.sh --method docker --arch arm64 --dest /srv/rpi4-sysroot

# 3. Зібрати
./scripts/build-system-build.sh rpi4-release -DRPI_SYSROOT=/srv/rpi4-sysroot

# 4. Розгорнути
./scripts/build-system-deploy.sh --preset rpi4-release --host 192.168.1.100 --user pi
```
