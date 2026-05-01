#!/usr/bin/env bash
# scripts/build-system-build.sh
#
# Обгортка над cmake --preset для зручної збірки.
#
# Використання:
#   ./scripts/build-system-build.sh <preset> [cmake-options...]
#
# Приклади:
#   ./scripts/build-system-build.sh rpi4-release
#   ./scripts/build-system-build.sh ubuntu2404-debug -DBUILD_TESTS=OFF
#   ./scripts/build-system-build.sh rpi4-release -DRPI_SYSROOT=/srv/rpi4-sysroot
#   ./scripts/build-system-build.sh --list
#
# Результат збірки: build/<preset>/bin/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    echo "Використання: $0 <preset> [cmake-options...]"
    echo "             $0 --list"
    echo ""
    echo "Доступні пресети:"
    cmake --list-presets=configure 2>/dev/null \
        | grep -v "^Available" | sed 's/^/  /' || true
    exit 0
}

# --- Перевірка CMake -------------------------------------------------------
check_cmake() {
    if ! command -v cmake &>/dev/null; then
        log_error "cmake не знайдено. Встановіть: sudo ./scripts/build-system-install-toolchains.sh cmake"
        exit 1
    fi
    local ver
    ver=$(cmake --version | head -1 | grep -oP '\d+\.\d+\.\d+')
    local major minor
    major=$(echo "$ver" | cut -d. -f1)
    minor=$(echo "$ver" | cut -d. -f2)
    if [[ $major -lt 3 ]] || { [[ $major -eq 3 ]] && [[ $minor -lt 28 ]]; }; then
        log_error "CMake ${ver} < 3.28. Оновіть CMake."
        exit 1
    fi
}

# --- Головна логіка --------------------------------------------------------
main() {
    if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        usage
    fi

    if [[ "$1" == "--list" ]]; then
        usage
    fi

    check_cmake

    local PRESET="$1"
    shift
    local EXTRA_ARGS=("$@")

    log_info "Пресет: ${PRESET}"
    log_info "Кореневий каталог: ${PROJECT_ROOT}"

    cd "${PROJECT_ROOT}"

    # --- Конфігурація -------------------------------------------------------
    log_info "=== Конфігурація ==="
    cmake --preset "${PRESET}" "${EXTRA_ARGS[@]}"

    # --- Збірка -------------------------------------------------------------
    log_info "=== Збірка ==="
    local JOBS
    JOBS=$(nproc 2>/dev/null || echo 4)
    cmake --build --preset "${PRESET}" --parallel "${JOBS}"

    # --- Результат ----------------------------------------------------------
    local BUILD_DIR="${PROJECT_ROOT}/build/${PRESET}"
    echo ""
    log_ok "=== Збірку завершено ==="
    log_info "Бінарники: ${BUILD_DIR}/bin/"
    log_info "Бібліотеки: ${BUILD_DIR}/lib/"

    if [[ -d "${BUILD_DIR}/bin" ]]; then
        echo ""
        echo "Артефакти:"
        find "${BUILD_DIR}/bin" -type f -executable | sort | sed 's/^/  /'
    fi
}

main "$@"
