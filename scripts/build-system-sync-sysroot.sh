#!/usr/bin/env bash
# scripts/build-system-sync-sysroot.sh
#
# Синхронізує sysroot з живого Raspberry Pi по SSH (rsync).
# Підтримує інкрементне оновлення — повторні виклики лише додають зміни.
#
# Вимоги на host:
#   Ubuntu/Debian : sudo apt install rsync
#   Arch/CachyOS  : sudo pacman -S rsync
#
# Вимоги на RPi:
#   - Запущений SSH (systemctl enable --now ssh)
#   - rsync (sudo apt install rsync  або  sudo pacman -S rsync)
#
# Використання:
#   ./scripts/build-system-sync-sysroot.sh --host <IP> --dest <шлях> [ОПЦІЇ]
#
# Приклади:
#   # Мінімальний sysroot (заголовки + бібліотеки)
#   ./scripts/build-system-sync-sysroot.sh --host 192.168.1.100 --dest /srv/rpi4-sysroot
#
#   # З вказаним користувачем та SSH ключем
#   ./scripts/build-system-sync-sysroot.sh \
#       --host 192.168.1.100 \
#       --user pi \
#       --key ~/.ssh/rpi_key \
#       --dest /srv/rpi4-sysroot
#
#   # Синхронізація з паролем (без ключа, потрібен sshpass)
#   ./scripts/build-system-sync-sysroot.sh --host 192.168.1.100 --dest /srv/rpi-sysroot --password

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# --- Значення за замовчуванням ---------------------------------------------
RPI_HOST=""
RPI_USER="pi"
RPI_PORT="22"
RPI_SSH_KEY=""
SYSROOT_DEST=""
USE_PASSWORD=false
DRY_RUN=false
EXTRA_DIRS=()

# --- Каталоги для синхронізації --------------------------------------------
# Мінімальний набір для крос-компіляції:
#   /usr/include  — системні заголовки
#   /usr/lib      — бібліотеки
#   /lib          — системні бібліотеки (libc, libm тощо)
#   /opt          — опціональні пакети (напр. VideoCore на RPi)
SYNC_DIRS=(
    "lib"
    "usr/include"
    "usr/lib"
    "usr/local/include"
    "usr/local/lib"
)

# Специфічно для Raspberry Pi (VideoCore GPU, camera)
RPI_EXTRA_DIRS=(
    "opt/vc"
)

# --- Парсинг аргументів ----------------------------------------------------
usage() {
    cat <<EOF
Використання: $0 --host <IP> --dest <шлях> [ОПЦІЇ]

Обов'язкові:
  --host <IP|hostname>    IP-адреса або hostname Raspberry Pi
  --dest <шлях>           Локальний шлях для sysroot

Опціональні:
  --user <ім'я>           SSH користувач (за замовчуванням: pi)
  --port <порт>           SSH порт (за замовчуванням: 22)
  --key  <шлях>           Шлях до SSH приватного ключа
  --password              Використовувати пароль (потрібен sshpass)
  --add-dir <шлях>        Додатковий каталог для синхронізації (можна кілька разів)
  --rpi-extras            Додати VideoCore (/opt/vc) для Raspberry Pi
  --dry-run               Показати що буде синхронізовано (без змін)
  --help                  Ця довідка

Приклади:
  $0 --host 192.168.1.100 --dest /srv/rpi4-sysroot
  $0 --host rpi4.local --user ubuntu --key ~/.ssh/id_rpi --dest /srv/rpi4-sysroot
  $0 --host 192.168.1.100 --dest /srv/rpi4-sysroot --rpi-extras
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)        RPI_HOST="$2";    shift 2 ;;
        --user)        RPI_USER="$2";    shift 2 ;;
        --port)        RPI_PORT="$2";    shift 2 ;;
        --key)         RPI_SSH_KEY="$2"; shift 2 ;;
        --dest)        SYSROOT_DEST="$2"; shift 2 ;;
        --password)    USE_PASSWORD=true; shift ;;
        --rpi-extras)  SYNC_DIRS+=("${RPI_EXTRA_DIRS[@]}"); shift ;;
        --add-dir)     EXTRA_DIRS+=("$2"); shift 2 ;;
        --dry-run)     DRY_RUN=true; shift ;;
        --help|-h)     usage ;;
        *) log_error "Невідомий аргумент: '$1'"; usage ;;
    esac
done

# --- Валідація -------------------------------------------------------------
if [[ -z "${RPI_HOST}" ]]; then
    log_error "--host обов'язковий"
    usage
fi
if [[ -z "${SYSROOT_DEST}" ]]; then
    log_error "--dest обов'язковий"
    usage
fi

SYNC_DIRS+=("${EXTRA_DIRS[@]}")

# --- Перевірка залежностей ------------------------------------------------
if ! command -v rsync &>/dev/null; then
    log_error "rsync не встановлено. Встановіть: sudo apt install rsync  або  sudo pacman -S rsync"
    exit 1
fi

if "${USE_PASSWORD}" && ! command -v sshpass &>/dev/null; then
    log_error "sshpass не встановлено. Встановіть: sudo apt install sshpass  або  sudo pacman -S sshpass"
    exit 1
fi

# --- Побудова SSH аргументів -----------------------------------------------
log_warn "SSH: StrictHostKeyChecking=no — host key не перевіряється (зручно для CI/автоматизації, не для публічних мереж)"
SSH_OPTS=(-p "${RPI_PORT}" -o StrictHostKeyChecking=no -o BatchMode=no)
if [[ -n "${RPI_SSH_KEY}" ]]; then
    SSH_OPTS+=(-i "${RPI_SSH_KEY}")
fi

printf -v RSYNC_RSH 'ssh'
for _o in "${SSH_OPTS[@]}"; do printf -v RSYNC_RSH '%s %q' "${RSYNC_RSH}" "${_o}"; done

if "${USE_PASSWORD}"; then
    log_warn "Режим з паролем — буде запитано пароль для кожного каталогу"
    printf -v RSYNC_RSH 'sshpass -e ssh'
    for _o in "${SSH_OPTS[@]}"; do printf -v RSYNC_RSH '%s %q' "${RSYNC_RSH}" "${_o}"; done
    if [[ -z "${SSHPASS:-}" ]]; then
        read -rsp "SSH пароль для ${RPI_USER}@${RPI_HOST}: " SSHPASS
        export SSHPASS
        echo ""
    fi
fi

# --- Основна синхронізація ------------------------------------------------
mkdir -p "${SYSROOT_DEST}"

log_info "=== Синхронізація sysroot ==="
log_info "Джерело : ${RPI_USER}@${RPI_HOST}"
log_info "Ціль    : ${SYSROOT_DEST}"
log_info "Каталоги: ${SYNC_DIRS[*]}"
echo ""

RSYNC_OPTS=(
    --archive           # зберігати права, посилання, час модифікації
    --delete            # видаляти файли, яких немає на джерелі
    --copy-links        # перетворювати симлінки на реальні файли
    --safe-links        # ігнорувати симлінки, що виходять за sysroot
    --no-perms          # не зберігати права (ми не root на host)
    --chmod=Du=rwx,go=rx,Fu=rw,go=r  # безпечні права на host
    --progress
    --stats
)

if "${DRY_RUN}"; then
    RSYNC_OPTS+=(--dry-run)
    log_warn "DRY RUN — реальних змін не буде"
fi

FAILED=()
for dir in "${SYNC_DIRS[@]}"; do
    log_info "Синхронізую /${dir} ..."
    if rsync "${RSYNC_OPTS[@]}" \
        --rsh="${RSYNC_RSH}" \
        "${RPI_USER}@${RPI_HOST}:/${dir}/" \
        "${SYSROOT_DEST}/${dir}/" 2>/dev/null; then
        log_ok "/${dir} — готово"
    else
        log_warn "/${dir} — пропущено (каталог може не існувати на RPi)"
        FAILED+=("${dir}")
    fi
    echo ""
done

# --- Виправлення абсолютних симлінків -------------------------------------
# Деякі .so файли мають абсолютні симлінки на /lib, /usr/lib.
# При крос-компіляції ld шукає їх відносно sysroot, тому їх треба
# перетворити на відносні.
log_info "=== Виправлення абсолютних симлінків ==="
if "${DRY_RUN}"; then
    log_warn "DRY RUN: виправлення симлінків пропущено"
else
    while IFS= read -r -d '' link; do
        target=$(readlink "${link}")
        if [[ "${target}" == /* ]]; then
            # Абсолютний симлінк → робимо відносним через sysroot
            new_target="${SYSROOT_DEST}${target}"
            if [[ -e "${new_target}" ]]; then
                rel_target=$(realpath --relative-to="$(dirname "${link}")" "${new_target}")
                ln -sf "${rel_target}" "${link}"
            fi
        fi
    done < <(find "${SYSROOT_DEST}" -type l -print0)
    log_ok "Симлінки виправлено"
fi

# --- Підсумок -------------------------------------------------------------
echo ""
log_ok "=== Синхронізацію завершено ==="
log_info "sysroot: ${SYSROOT_DEST}"
echo ""
echo "Використання з CMake:"
echo "  cmake --preset rpi4-release -DRPI_SYSROOT=${SYSROOT_DEST}"
echo "  # або через build.sh:"
echo "  ./scripts/build-system-build.sh rpi4-release -DRPI_SYSROOT=${SYSROOT_DEST}"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    log_warn "Пропущені каталоги (не критично): ${FAILED[*]}"
fi
