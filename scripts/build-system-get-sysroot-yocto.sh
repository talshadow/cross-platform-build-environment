#!/usr/bin/env bash
# scripts/build-system-get-sysroot-yocto.sh
#
# Допомагає отримати та підготувати sysroot для Yocto Linux.
# Yocto надає sysroot через SDK-інсталятор (.sh скрипт).
#
# Методи:
#   sdk     — встановити Yocto SDK з .sh інсталятора
#   extract — витягнути лише sysroot з SDK без повного встановлення
#   check   — перевірити вже активоване SDK середовище
#
# Використання:
#   ./scripts/build-system-get-sysroot-yocto.sh --method sdk     --installer poky-*.sh [--dest /opt/poky]
#   ./scripts/build-system-get-sysroot-yocto.sh --method extract --installer poky-*.sh --dest /srv/yocto-sysroot
#   ./scripts/build-system-get-sysroot-yocto.sh --method check
#
# Після встановлення SDK:
#   source /opt/poky/<ver>/environment-setup-<target>-poky-linux
#   cmake --preset yocto-release

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

METHOD=""
INSTALLER=""
DEST=""

usage() {
    cat <<'EOF'
Використання: build-system-get-sysroot-yocto.sh --method <метод> [ОПЦІЇ]

Методи:
  sdk       Встановити повний Yocto SDK (рекомендовано)
            --installer <поки-*.sh>   Шлях до SDK інсталятора
            --dest      <шлях>        Куди встановити (за замовч.: /opt/poky)

  extract   Витягти тільки target sysroot без повного SDK
            --installer <поки-*.sh>   Шлях до SDK інсталятора
            --dest      <шлях>        Куди зберегти sysroot

  check     Перевірити поточне середовище (чи активовано SDK)

Де взяти SDK інсталятор:
  1. Зберіть власний у Yocto: bitbake <image> -c populate_sdk
     Результат: build/tmp/deploy/sdk/poky-*.sh

  2. Завантажте готовий (для Raspberry Pi):
     https://downloads.yoctoproject.org/releases/yocto/

  3. З поточного Yocto build-сервера (якщо є SSH доступ):
     scp user@yocto-server:/path/to/poky-*.sh .

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --method)      METHOD="$2";    shift 2 ;;
        --installer)   INSTALLER="$2"; shift 2 ;;
        --dest)        DEST="$2";      shift 2 ;;
        --help|-h)     usage ;;
        *) log_error "Невідомий аргумент: '$1'"; usage ;;
    esac
done

[[ -z "${METHOD}" ]] && { log_error "--method обов'язковий"; usage; }

# ===========================================================================
# МЕТОД 1: Повне встановлення SDK
# ===========================================================================
method_sdk() {
    [[ -z "${INSTALLER}" ]] && { log_error "--installer обов'язковий для method=sdk"; exit 1; }
    [[ ! -f "${INSTALLER}" ]] && { log_error "Інсталятор не знайдено: ${INSTALLER}"; exit 1; }

    local install_dir="${DEST:-/opt/poky}"

    log_info "=== Встановлення Yocto SDK ==="
    log_info "Інсталятор : ${INSTALLER}"
    log_info "Ціль       : ${install_dir}"
    echo ""

    chmod +x "${INSTALLER}"
    bash "${INSTALLER}" -d "${install_dir}" -y

    log_ok "SDK встановлено в: ${install_dir}"
    echo ""

    # Знаходимо environment-setup скрипт
    local env_scripts
    mapfile -t env_scripts < <(find "${install_dir}" -name "environment-setup-*" -type f 2>/dev/null)

    if [[ ${#env_scripts[@]} -eq 0 ]]; then
        log_warn "environment-setup-* скрипт не знайдено в ${install_dir}"
    else
        echo "Знайдені SDK середовища:"
        for env in "${env_scripts[@]}"; do
            echo "  ${env}"
        done
        echo ""
        echo "Для активації SDK:"
        echo "  source ${env_scripts[0]}"
        echo ""
        echo "Після активації запустіть збірку:"
        echo "  cmake --preset yocto-release"
        echo "  # або:"
        echo "  ./scripts/build-system-build.sh yocto-release"
    fi
}

# ===========================================================================
# МЕТОД 2: Витягнути тільки sysroot
# ===========================================================================
method_extract() {
    [[ -z "${INSTALLER}" ]] && { log_error "--installer обов'язковий для method=extract"; exit 1; }
    [[ -z "${DEST}" ]]      && { log_error "--dest обов'язковий для method=extract";      exit 1; }
    [[ ! -f "${INSTALLER}" ]] && { log_error "Інсталятор не знайдено: ${INSTALLER}"; exit 1; }

    log_info "=== Витягнення sysroot з Yocto SDK ==="
    log_info "Інсталятор : ${INSTALLER}"
    log_info "Ціль       : ${DEST}"

    # Встановлюємо SDK у тимчасовий каталог
    local TMP_SDK
    TMP_SDK=$(mktemp -d)
    log_info "Тимчасовий SDK: ${TMP_SDK}"

    chmod +x "${INSTALLER}"
    bash "${INSTALLER}" -d "${TMP_SDK}" -y

    # Знаходимо target sysroot
    local target_sysroot
    target_sysroot=$(find "${TMP_SDK}" -maxdepth 4 \
        -name "sysroots" -type d 2>/dev/null | head -1)

    if [[ -z "${target_sysroot}" ]]; then
        log_error "sysroots не знайдено в SDK"
        rm -rf "${TMP_SDK}"
        exit 1
    fi

    # SDK містить два sysroot: host (x86_64-*) та target (arm*, aarch64*)
    local target_dir
    target_dir=$(find "${target_sysroot}" -maxdepth 1 -mindepth 1 -type d \
        ! -name "x86_64*" ! -name "*sdk*" 2>/dev/null | head -1)

    if [[ -z "${target_dir}" ]]; then
        log_warn "Target sysroot не знайдено автоматично. Вміст ${target_sysroot}:"
        ls "${target_sysroot}"
        log_error "Вкажіть правильний каталог вручну."
        rm -rf "${TMP_SDK}"
        exit 1
    fi

    log_info "Target sysroot знайдено: ${target_dir}"
    log_info "Копіювання..."

    mkdir -p "${DEST}"
    rsync -a --copy-links --safe-links "${target_dir}/" "${DEST}/"

    log_ok "sysroot скопійовано"

    # Очищення
    rm -rf "${TMP_SDK}"

    echo ""
    log_ok "=== sysroot готовий: ${DEST} ==="
    echo ""
    echo "Використання:"
    echo "  cmake --preset yocto-release -DYOCTO_SDK_SYSROOT=${DEST}"
}

# ===========================================================================
# МЕТОД 3: Перевірка поточного середовища
# ===========================================================================
method_check() {
    log_info "=== Перевірка Yocto SDK середовища ==="
    echo ""

    local ok=true

    check_var() {
        local var="$1"
        if [[ -n "${!var:-}" ]]; then
            printf "  ${GREEN}✓${NC} %-30s = %s\n" "${var}" "${!var}"
        else
            printf "  ${RED}✗${NC} %-30s не визначена\n" "${var}"
            ok=false
        fi
    }

    check_var "OECORE_TARGET_ARCH"
    check_var "SDKTARGETSYSROOT"
    check_var "OECORE_NATIVE_SYSROOT"
    check_var "CC"
    check_var "CXX"
    check_var "LD"
    check_var "AR"

    echo ""

    if $ok; then
        log_ok "SDK середовище активне. Готово до збірки:"
        echo "  cmake --preset yocto-release"
    else
        log_error "SDK середовище НЕ активне або активоване неповністю."
        echo ""
        echo "Активуйте SDK:"
        echo "  source /opt/poky/<version>/environment-setup-<target>-poky-linux"
        echo ""
        echo "Якщо SDK не встановлено:"
        echo "  ./scripts/build-system-get-sysroot-yocto.sh --method sdk --installer poky-*.sh"
        exit 1
    fi
}

case "${METHOD}" in
    sdk)     method_sdk     ;;
    extract) method_extract ;;
    check)   method_check   ;;
    *)
        log_error "Невідомий метод: '${METHOD}'. Допустимі: sdk, extract, check"
        usage
        ;;
esac
