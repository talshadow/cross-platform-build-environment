#!/usr/bin/env bash
# scripts/build-system-get-sysroot-rpi.sh
#
# Отримує sysroot для Raspberry Pi одним із трьох методів:
#
#   METHOD=image   — розпаковує образ Raspberry Pi OS (.img) без фізичного RPi
#   METHOD=docker  — витягує sysroot з офіційного Docker-образу (інтернет)
#   METHOD=live    — синхронізує sysroot з живого RPi по SSH (→ build-system-sync-sysroot.sh)
#
# Використання:
#   ./scripts/build-system-get-sysroot-rpi.sh --method image  --image rpi.img --dest /srv/rpi4-sysroot
#   ./scripts/build-system-get-sysroot-rpi.sh --method docker --arch arm64    --dest /srv/rpi4-sysroot
#   ./scripts/build-system-get-sysroot-rpi.sh --method live   --host 192.168.1.100 --dest /srv/rpi4-sysroot
#
# Після виконання:
#   cmake --preset rpi4-release -DRPI_SYSROOT=/srv/rpi4-sysroot

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

METHOD=""
DEST=""
IMAGE_PATH=""
DOCKER_ARCH="arm64"       # arm64 або arm/v7
RPI_HOST=""
RPI_USER="pi"
RPI_PORT="22"
RPI_KEY=""
EXTRA_PACKAGES=""

usage() {
    cat <<'EOF'
Використання: build-system-get-sysroot-rpi.sh --method <метод> --dest <шлях> [ОПЦІЇ]

Методи:
  image   Розпакувати sysroot з образу Raspberry Pi OS (.img)
          Опції: --image <шлях до .img або .img.xz>

  docker  Витягти sysroot з Docker-образу (потрібен Docker + інтернет)
          Опції: --arch <arm64|arm/v7>   (за замовчуванням: arm64)

  live    Синхронізувати sysroot з живого RPi по SSH (обгортка build-system-sync-sysroot.sh)
          Опції: --host <IP>  --user <user>  --port <22>  --key <шлях>

Загальні:
  --dest <шлях>            Куди зберегти sysroot (обов'язково)
  --extra-packages <список> Додаткові deb-пакети для встановлення (через пробіл або кому)
  --help                   Ця довідка

Приклади:
  # Без RPi — через Docker (найпростіший спосіб для RPi 3/4/5)
  ./scripts/build-system-get-sysroot-rpi.sh --method docker --arch arm64 --dest /srv/rpi4-sysroot

  # З образу (не потрібний ні RPi, ні Docker)
  wget https://downloads.raspberrypi.org/raspios_lite_arm64/images/.../xxx.img.xz
  ./scripts/build-system-get-sysroot-rpi.sh --method image --image xxx.img.xz --dest /srv/rpi4-sysroot

  # З живого RPi
  ./scripts/build-system-get-sysroot-rpi.sh --method live --host 192.168.1.100 --dest /srv/rpi4-sysroot
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --method)  METHOD="$2";      shift 2 ;;
        --dest)    DEST="$2";        shift 2 ;;
        --image)   IMAGE_PATH="$2";  shift 2 ;;
        --arch)    DOCKER_ARCH="$2"; shift 2 ;;
        --host)    RPI_HOST="$2";    shift 2 ;;
        --user)    RPI_USER="$2";    shift 2 ;;
        --port)    RPI_PORT="$2";    shift 2 ;;
        --key)             RPI_KEY="$2";         shift 2 ;;
        --extra-packages)  EXTRA_PACKAGES="$2";  shift 2 ;;
        --help|-h) usage ;;
        *) log_error "Невідомий аргумент: '$1'"; usage ;;
    esac
done

[[ -z "${METHOD}" ]] && { log_error "--method обов'язковий"; usage; }
[[ -z "${DEST}" ]]   && { log_error "--dest обов'язковий";   usage; }

mkdir -p "${DEST}"

# ===========================================================================
# МЕТОД 1: Розпакування з образу .img
# ===========================================================================
method_image() {
    [[ -z "${IMAGE_PATH}" ]] && { log_error "--image обов'язковий для method=image"; exit 1; }

    # --- Залежності ---------------------------------------------------------
    for dep in losetup partprobe mount findmnt; do
        command -v "${dep}" &>/dev/null || {
            log_error "'${dep}' не знайдено. Встановіть: sudo apt install util-linux mount  або  sudo pacman -S util-linux"
            exit 1
        }
    done

    # --- Розпакування xz (якщо потрібно) -----------------------------------
    local img="${IMAGE_PATH}"
    if [[ "${img}" == *.xz ]]; then
        log_info "Розпаковую xz-архів..."
        command -v xz &>/dev/null || { log_error "xz не знайдено. Встановіть: sudo apt install xz-utils  або  sudo pacman -S xz"; exit 1; }
        xz --decompress --keep --stdout "${img}" > "${DEST}/rpi.img"
        img="${DEST}/rpi.img"
        log_ok "Розпаковано: ${img}"
    fi

    # --- Потрібен root для losetup/mount ------------------------------------
    if [[ $EUID -ne 0 ]]; then
        log_error "Для method=image потрібен root (sudo)"
        exit 1
    fi

    local LOOP_DEV
    LOOP_DEV=$(losetup --find --show --partscan "${img}")
    log_info "Loop device: ${LOOP_DEV}"

    # Raspberry Pi OS: partition 1 = boot (FAT), partition 2 = rootfs (ext4)
    local PART="${LOOP_DEV}p2"
    local MOUNT_DIR
    MOUNT_DIR=$(mktemp -d)

    log_info "Монтування ${PART} → ${MOUNT_DIR}"
    mount -o ro "${PART}" "${MOUNT_DIR}"

    log_info "Копіювання sysroot..."
    local SYNC_DIRS=(lib usr/include usr/lib usr/local/include usr/local/lib opt/vc)
    for dir in "${SYNC_DIRS[@]}"; do
        if [[ -d "${MOUNT_DIR}/${dir}" ]]; then
            mkdir -p "${DEST}/${dir}"
            rsync -a --copy-links --safe-links "${MOUNT_DIR}/${dir}/" "${DEST}/${dir}/" 2>/dev/null || true
            log_ok "/${dir} скопійовано"
        fi
    done

    log_info "Розмонтування..."
    umount "${MOUNT_DIR}"
    rmdir "${MOUNT_DIR}"
    losetup --detach "${LOOP_DEV}"

    [[ "${IMAGE_PATH}" == *.xz ]] && rm -f "${DEST}/rpi.img"

    fixup_symlinks
}

# ===========================================================================
# МЕТОД 2: Docker-образ
# ===========================================================================
method_docker() {
    command -v docker &>/dev/null || {
        log_error "Docker не встановлено. Встановіть: https://docs.docker.com/engine/install/ubuntu/"
        exit 1
    }

    # Перевірка підтримки мультиарх (QEMU) через binfmt_misc ядра.
    # Не завантажуємо тестовий образ — перевіряємо наявність запису в /proc напряму,
    # щоб уникнути хибних помилок через відсутність образу в локальному кеші Docker.
    local _binfmt_entry
    case "${DOCKER_ARCH}" in
        arm64|aarch64)      _binfmt_entry="qemu-aarch64" ;;
        arm/v7|armhf|arm32) _binfmt_entry="qemu-arm"     ;;
        arm/v6|armv6)       _binfmt_entry="qemu-arm"     ;;
        *)                  _binfmt_entry="qemu-${DOCKER_ARCH%%/*}" ;;
    esac
    if [[ ! -f "/proc/sys/fs/binfmt_misc/${_binfmt_entry}" ]]; then
        log_warn "QEMU binfmt (${_binfmt_entry}) не знайдено — налаштування мультиарх емуляції..."
        docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    fi

    # Офіційний образ Raspberry Pi OS
    local DOCKER_IMAGE="balenalib/raspberry-pi-debian:latest"
    case "${DOCKER_ARCH}" in
        arm64|aarch64)
            DOCKER_IMAGE="arm64v8/debian:bookworm-slim"
            log_info "Використовую образ: ${DOCKER_IMAGE} (Debian arm64, сумісний з RPi 3/4/5 OS)"
            ;;
        arm/v7|armhf|arm32)
            DOCKER_IMAGE="arm32v7/debian:bookworm-slim"
            log_info "Використовую образ: ${DOCKER_IMAGE} (Debian armhf, сумісний з RPi 2/3 32-bit)"
            ;;
        arm/v6|armv6)
            DOCKER_IMAGE="arm32v6/debian:bookworm-slim"
            log_warn "ARMv6: використовується Debian armv6. Для Raspberry Pi OS - використайте method=image"
            ;;
        *)
            log_error "Невідома архітектура: '${DOCKER_ARCH}'. Допустимі: arm64, arm/v7, arm/v6"
            exit 1
            ;;
    esac

    log_info "Завантаження образу ${DOCKER_IMAGE}..."
    docker pull --platform "linux/${DOCKER_ARCH}" "${DOCKER_IMAGE}"

    # Базові dev-пакети + будь-які extra-packages від користувача
    local BASE_PACKAGES="libc6-dev libstdc++-12-dev libgcc-12-dev libssl-dev zlib1g-dev"
    local EXTRA_PKG_LIST=""
    if [[ -n "${EXTRA_PACKAGES}" ]]; then
        # дозволяємо роздільники: пробіл, кома
        EXTRA_PKG_LIST=$(echo "${EXTRA_PACKAGES}" | tr ',' ' ')
        log_info "Додаткові пакети: ${EXTRA_PKG_LIST}"
    fi

    log_info "Запуск контейнера..."
    local CONTAINER_ID
    CONTAINER_ID=$(docker run -d --platform "linux/${DOCKER_ARCH}" "${DOCKER_IMAGE}" sleep infinity)
    log_info "Контейнер: ${CONTAINER_ID}"

    log_info "Встановлення пакетів розробки..."
    # shellcheck disable=SC2086
    docker exec "${CONTAINER_ID}" bash -c "
        apt-get update -qq &&
        apt-get install -y --no-install-recommends ${BASE_PACKAGES} ${EXTRA_PKG_LIST}
    "

    log_info "Копіювання sysroot з контейнера..."
    local DIRS=(lib usr/include usr/lib usr/local)
    for dir in "${DIRS[@]}"; do
        log_info "  Копіюю /${dir}..."
        mkdir -p "${DEST}/${dir}"
        docker cp "${CONTAINER_ID}:/${dir}/." "${DEST}/${dir}/" 2>/dev/null || true
        log_ok "  /${dir} готово"
    done

    log_info "Зупинка контейнера..."
    docker stop "${CONTAINER_ID}" &>/dev/null
    docker rm   "${CONTAINER_ID}" &>/dev/null

    fixup_symlinks
}

# ===========================================================================
# МЕТОД 3: Живий RPi (делегація до build-system-sync-sysroot.sh)
# ===========================================================================
method_live() {
    [[ -z "${RPI_HOST}" ]] && { log_error "--host обов'язковий для method=live"; exit 1; }

    local SYNC_SCRIPT="${SCRIPT_DIR}/build-system-sync-sysroot.sh"
    if [[ ! -f "${SYNC_SCRIPT}" ]]; then
        log_error "scripts/build-system-sync-sysroot.sh не знайдено"
        exit 1
    fi

    local ARGS=(--host "${RPI_HOST}" --user "${RPI_USER}" --port "${RPI_PORT}" --dest "${DEST}" --rpi-extras)
    [[ -n "${RPI_KEY}" ]] && ARGS+=(--key "${RPI_KEY}")

    bash "${SYNC_SCRIPT}" "${ARGS[@]}"
}

# ===========================================================================
# Виправлення абсолютних симлінків
# ===========================================================================
fixup_symlinks() {
    log_info "=== Виправлення абсолютних симлінків ==="
    while IFS= read -r -d '' link; do
        local target
        target=$(readlink "${link}")
        if [[ "${target}" == /* ]]; then
            local new_target="${DEST}${target}"
            if [[ -e "${new_target}" ]]; then
                local rel_target
                rel_target=$(realpath --relative-to="$(dirname "${link}")" "${new_target}")
                ln -sf "${rel_target}" "${link}"
            fi
        fi
    done < <(find "${DEST}" -type l -print0)
    log_ok "Симлінки виправлено"

    echo ""
    log_ok "=== sysroot готовий: ${DEST} ==="
    echo ""
    echo "Використання:"
    echo "  cmake --preset rpi4-release -DRPI_SYSROOT=${DEST}"
    echo "  # або:"
    echo "  ./scripts/build-system-build.sh rpi4-release -DRPI_SYSROOT=${DEST}"
}

# --- Запуск ----------------------------------------------------------------
case "${METHOD}" in
    image)  method_image  ;;
    docker) method_docker ;;
    live)   method_live   ;;
    *)
        log_error "Невідомий метод: '${METHOD}'. Допустимі: image, docker, live"
        usage
        ;;
esac
