#!/usr/bin/env bash
# scripts/build-system-deploy.sh
#
# Розгортає зібрані артефакти на цільову систему по SSH/rsync.
# Підтримує Raspberry Pi та будь-який Linux з SSH.
#
# Використання:
#   ./scripts/build-system-deploy.sh --preset <preset> --host <IP> [ОПЦІЇ]
#
# Приклади:
#   ./scripts/build-system-deploy.sh --preset rpi4-release --host 192.168.1.100
#   ./scripts/build-system-deploy.sh --preset rpi4-release --host rpi4.local \
#       --user pi --key ~/.ssh/rpi_key --remote-dir /home/pi/app
#   ./scripts/build-system-deploy.sh --preset rpi4-release --host 192.168.1.100 \
#       --run my_app --run-args "--config /etc/app.cfg"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# --- Значення за замовчуванням ---------------------------------------------
PRESET=""
TARGET_HOST=""
TARGET_USER="pi"
TARGET_PORT="22"
SSH_KEY=""
REMOTE_DIR="/home/pi/app"
RUN_BINARY=""
RUN_ARGS=""
STRIP_BINARIES=false
USE_PASSWORD=false

usage() {
    cat <<EOF
Використання: $0 --preset <preset> --host <IP> [ОПЦІЇ]

Обов'язкові:
  --preset <ім'я>         CMake пресет (напр. rpi4-release)
  --host <IP|hostname>    Адреса цільової системи

Опціональні:
  --user <ім'я>           SSH користувач (за замовчуванням: pi)
  --port <порт>           SSH порт (за замовчуванням: 22)
  --key  <шлях>           Шлях до SSH ключа
  --password              Використовувати пароль
  --remote-dir <шлях>     Каталог на цільовій системі (за замовчуванням: /home/pi/app)
  --strip                 Strip символи з бінарників перед відправкою
  --run <бінарник>        Запустити програму після розгортання
  --run-args <аргументи>  Аргументи для запуску
  --help                  Ця довідка
EOF
    exit 0
}

# --- Парсинг аргументів ---------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --preset)      PRESET="$2";       shift 2 ;;
        --host)        TARGET_HOST="$2";  shift 2 ;;
        --user)        TARGET_USER="$2";  shift 2 ;;
        --port)        TARGET_PORT="$2";  shift 2 ;;
        --key)         SSH_KEY="$2";      shift 2 ;;
        --remote-dir)  REMOTE_DIR="$2";   shift 2 ;;
        --strip)       STRIP_BINARIES=true; shift ;;
        --run)         RUN_BINARY="$2";   shift 2 ;;
        --run-args)    RUN_ARGS="$2";     shift 2 ;;
        --password)    USE_PASSWORD=true; shift ;;
        --help|-h)     usage ;;
        *) log_error "Невідомий аргумент: '$1'"; usage ;;
    esac
done

if [[ -z "${PRESET}" || -z "${TARGET_HOST}" ]]; then
    log_error "--preset та --host обов'язкові"
    usage
fi

# --- Визначення каталогу збірки -------------------------------------------
BUILD_DIR="${PROJECT_ROOT}/build/${PRESET}"
BIN_DIR="${BUILD_DIR}/bin"
LIB_DIR="${BUILD_DIR}/lib"

if [[ ! -d "${BUILD_DIR}" ]]; then
    log_error "Каталог збірки не існує: ${BUILD_DIR}"
    log_error "Спочатку виконайте: ./scripts/build-system-build.sh ${PRESET}"
    exit 1
fi

# --- SSH налаштування -------------------------------------------------------
# StrictHostKeyChecking=no: вимикає перевірку host key, тому перше підключення
# до нового хоста не потребує підтвердження. Зручно для автоматизації,
# але зменшує захист від MITM-атак — використовуйте лише в довіреній мережі.
log_warn "SSH: StrictHostKeyChecking=no — host key не перевіряється (зручно для CI/автоматизації, не для публічних мереж)"
SSH_OPTS=(-p "${TARGET_PORT}" -o StrictHostKeyChecking=no)
if [[ -n "${SSH_KEY}" ]]; then
    SSH_OPTS+=(-i "${SSH_KEY}")
fi

SSH_CMD=(ssh "${SSH_OPTS[@]}")
printf -v RSYNC_RSH 'ssh'
for _o in "${SSH_OPTS[@]}"; do printf -v RSYNC_RSH '%s %q' "${RSYNC_RSH}" "${_o}"; done

if "${USE_PASSWORD}"; then
    if ! command -v sshpass &>/dev/null; then
        log_error "sshpass не встановлено. Встановіть: sudo apt install sshpass  або  sudo pacman -S sshpass"
        exit 1
    fi
    if [[ -z "${SSHPASS:-}" ]]; then
        read -rsp "SSH пароль для ${TARGET_USER}@${TARGET_HOST}: " SSHPASS
        export SSHPASS
        echo ""
    fi
    SSH_CMD=(sshpass -e ssh "${SSH_OPTS[@]}")
    printf -v RSYNC_RSH 'sshpass -e ssh'
    for _o in "${SSH_OPTS[@]}"; do printf -v RSYNC_RSH '%s %q' "${RSYNC_RSH}" "${_o}"; done
fi

# --- Strip бінарників (опціонально) ----------------------------------------
if "${STRIP_BINARIES}" && [[ -d "${BIN_DIR}" ]]; then
    log_info "Strip бінарників..."

    # Визначаємо strip утиліту для крос-компіляції
    STRIP_CMD="strip"
    case "${PRESET}" in
        rpi1*|rpi2*) STRIP_CMD="arm-linux-gnueabihf-strip" ;;
        rpi3*|rpi4*|rpi5*) STRIP_CMD="aarch64-linux-gnu-strip" ;;
    esac

    if command -v "${STRIP_CMD}" &>/dev/null; then
        find "${BIN_DIR}" -type f -executable -exec "${STRIP_CMD}" --strip-unneeded {} \;
        log_ok "Strip завершено (${STRIP_CMD})"
    else
        log_warn "Strip утиліта '${STRIP_CMD}' не знайдена, пропущено"
    fi
fi

# --- Розгортання -----------------------------------------------------------
log_info "=== Розгортання ==="
log_info "Пресет : ${PRESET}"
log_info "Ціль   : ${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}"

# Створення каталогу на цільовій системі
"${SSH_CMD[@]}" "${TARGET_USER}@${TARGET_HOST}" -- mkdir -p "${REMOTE_DIR}"

# Копіювання бінарників
if [[ -d "${BIN_DIR}" ]]; then
    log_info "Копіювання бінарників..."
    rsync -avz --progress \
        --rsh="${RSYNC_RSH}" \
        "${BIN_DIR}/" \
        "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/"
fi

# Копіювання бібліотек (якщо є)
if [[ -d "${LIB_DIR}" ]] && [[ -n "$(ls -A "${LIB_DIR}" 2>/dev/null)" ]]; then
    log_info "Копіювання бібліотек..."
    rsync -avz --progress \
        --rsh="${RSYNC_RSH}" \
        "${LIB_DIR}/" \
        "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DIR}/lib/"
fi

log_ok "=== Розгортання завершено ==="

# --- Запуск на цільовій системі (опціонально) -----------------------------
if [[ -n "${RUN_BINARY}" ]]; then
    log_info "=== Запуск: ${RUN_BINARY} ${RUN_ARGS} ==="
    read -r -a _run_args_array <<< "${RUN_ARGS}"
    _safe_remote="cd $(printf '%q' "${REMOTE_DIR}") && ./$(printf '%q' "${RUN_BINARY}")"
    for _a in "${_run_args_array[@]+"${_run_args_array[@]}"}"; do
        _safe_remote+=" $(printf '%q' "${_a}")"
    done
    "${SSH_CMD[@]}" "${TARGET_USER}@${TARGET_HOST}" -- "${_safe_remote}"
fi
