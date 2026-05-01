#!/usr/bin/env bash
# scripts/build-system-install-toolchains.sh
#
# Встановлює всі необхідні крос-компілятори для збірки під цільові платформи.
# Підтримувані host-системи: Ubuntu 20.04, Ubuntu 24.04, Arch Linux
#
# Використання:
#   chmod +x scripts/build-system-install-toolchains.sh
#   ./scripts/build-system-install-toolchains.sh [ВАРІАНТ...]
#
# Варіанти:
#   all       — встановити все (за замовчуванням)
#   rpi-arm32 — крос-компілятор для RPi 1/2 (arm-linux-gnueabihf)
#   rpi-arm64 — крос-компілятор для RPi 3/4/5 (aarch64-linux-gnu)
#   native20  — GCC 10 для Ubuntu 20.04
#   native24  — GCC 13/14 для Ubuntu 24.04
#   ninja     — збирач Ninja (потрібен для CMake presets)
#   gdb       — cross-GDB для remote debug (gdb-multiarch / gdb)
#
# Yocto: toolchain встановлюється з SDK-інсталятора (./poky-*.sh),
#        цей скрипт Yocto SDK не встановлює.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# --- Перевірка прав --------------------------------------------------------
require_sudo() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Потрібні права root. Запустіть через sudo або як root."
        exit 1
    fi
}

# --- Визначення дистрибутиву -----------------------------------------------
# Виводить: "ubuntu:20.04", "ubuntu:24.04", "arch", або завершує з помилкою.
detect_distro() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Не вдалося визначити ОС (відсутній /etc/os-release)"
        exit 1
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    case "${ID}" in
        ubuntu) echo "ubuntu:${VERSION_ID}" ;;
        arch)   echo "arch" ;;
        *)
            log_warn "Виявлена ОС: ${PRETTY_NAME}. Скрипт розрахований на Ubuntu або Arch Linux."
            log_warn "Продовжити? [y/N] "
            read -r answer
            [[ "${answer}" =~ ^[Yy]$ ]] || exit 0
            echo "unknown"
            ;;
    esac
}

# --- Встановлення пакетів --------------------------------------------------
# Підтримує apt (Ubuntu) і pacman (Arch).
_PKG_MANAGER=""  # встановлюється в main()

install_packages() {
    log_info "Встановлення: $*"
    case "${_PKG_MANAGER}" in
        apt)
            apt-get install -y --no-install-recommends "$@"
            ;;
        pacman)
            pacman -S --needed --noconfirm "$@"
            ;;
    esac
    log_ok "Встановлено: $*"
}

pkg_update() {
    case "${_PKG_MANAGER}" in
        apt)    log_info "Оновлення apt...";    apt-get update -qq ;;
        pacman) log_info "Оновлення pacman..."; pacman -Sy --noconfirm ;;
    esac
}

# --- Функції встановлення --------------------------------------------------
install_rpi_arm32() {
    log_info "=== Крос-компілятор RPi 1/2 (arm-linux-gnueabihf) ==="
    case "${_PKG_MANAGER}" in
        apt)
            install_packages \
                gcc-arm-linux-gnueabihf \
                g++-arm-linux-gnueabihf \
                binutils-arm-linux-gnueabihf
            ;;
        pacman)
            # AUR: arm-linux-gnueabihf-gcc; у офіційних репо — немає.
            if command -v yay &>/dev/null; then
                log_info "Встановлення через yay (AUR)..."
                # yay не потребує root; запускаємо від звичайного користувача
                local real_user="${SUDO_USER:-${USER}}"
                sudo -u "${real_user}" yay -S --needed --noconfirm \
                    arm-linux-gnueabihf-gcc \
                    arm-linux-gnueabihf-binutils \
                    arm-linux-gnueabihf-glibc
            else
                log_warn "yay не знайдено. Встановіть AUR-хелпер (yay/paru) або"
                log_warn "вручну: arm-linux-gnueabihf-gcc з AUR."
                return 1
            fi
            ;;
    esac

    log_info "Перевірка:"
    arm-linux-gnueabihf-gcc --version | head -1

    log_warn "УВАГА (RPi 1/Zero): arm-linux-gnueabihf скомпільовано"
    log_warn "з ARMv7 baseline. Для ARMv6 бінарники можуть не запуститись."
    log_warn "Використовуйте офіційний RPi Foundation toolchain для ARMv6."
}

install_rpi_arm64() {
    log_info "=== Крос-компілятори RPi 4 (GCC 12) та RPi 5 (GCC 13) ==="
    case "${_PKG_MANAGER}" in
        apt)
            # gcc-12 доступний починаючи з Ubuntu 22.04; на 20.04 може
            # потребувати PPA (toolchain-r/test). gcc-13 — тільки 23.10+.
            local pkgs=(binutils-aarch64-linux-gnu)
            for ver in 12 13; do
                if apt-cache show "gcc-${ver}-aarch64-linux-gnu" &>/dev/null; then
                    pkgs+=(
                        "gcc-${ver}-aarch64-linux-gnu"
                        "g++-${ver}-aarch64-linux-gnu"
                    )
                else
                    log_warn "gcc-${ver}-aarch64-linux-gnu не доступний в поточних репозиторіях, пропущено."
                fi
            done
            install_packages "${pkgs[@]}"
            ;;
        pacman)
            # Arch: aarch64-linux-gnu-gcc з community/extra репо
            install_packages \
                aarch64-linux-gnu-gcc \
                aarch64-linux-gnu-binutils \
                aarch64-linux-gnu-glibc
            log_warn "Arch: пакет aarch64-linux-gnu-gcc не є версованим (GCC 12/13)."
            log_warn "CMake toolchain використає неверсований aarch64-linux-gnu-gcc."
            ;;
    esac

    log_info "Перевірка:"
    for cc in aarch64-linux-gnu-gcc-12 aarch64-linux-gnu-gcc-13 aarch64-linux-gnu-gcc; do
        if command -v "${cc}" &>/dev/null; then
            "${cc}" --version | head -1
        fi
    done
}

install_native_gcc_ubuntu20() {
    log_info "=== GCC 10 для Ubuntu 20.04 ==="
    install_packages gcc-10 g++-10

    # Встановлюємо GCC 10 як альтернативу (не змінюємо default)
    update-alternatives --install /usr/bin/gcc-for-build gcc-for-build \
        "$(which gcc-10)" 10 || true
    log_info "Перевірка:"
    gcc-10 --version | head -1
}

install_native_gcc_ubuntu24() {
    log_info "=== GCC 13 та GCC 14 для Ubuntu 24.04 ==="
    install_packages gcc-13 g++-13

    # GCC 14 може бути в universe
    if apt-cache show gcc-14 &>/dev/null; then
        install_packages gcc-14 g++-14
    else
        log_warn "gcc-14 недоступний в поточних репозиторіях, пропущено."
    fi

    log_info "Перевірка:"
    gcc-13 --version | head -1
}

install_native_gcc_arch() {
    log_info "=== GCC (нативний) для Arch Linux ==="
    install_packages gcc

    log_info "Перевірка:"
    gcc --version | head -1
}

install_ninja() {
    log_info "=== Ninja build system ==="
    case "${_PKG_MANAGER}" in
        apt)    install_packages ninja-build ;;
        pacman) install_packages ninja ;;
    esac
    log_info "Перевірка:"
    ninja --version
}

install_gdb() {
    log_info "=== Cross-GDB для remote debug ==="
    case "${_PKG_MANAGER}" in
        apt)
            # gdb-multiarch: один бінарник з підтримкою всіх arch (AArch64, ARM32 тощо).
            # На Ubuntu 20.04/24.04 це єдиний офіційний спосіб отримати AArch64 GDB.
            install_packages gdb-multiarch
            log_info "Бінарник: $(command -v gdb-multiarch)"
            ;;
        pacman)
            # На Arch gdb збирається з --enable-targets=all — multiarch з коробки.
            install_packages gdb
            log_info "Бінарник: $(command -v gdb)"
            ;;
    esac

    log_info "Перевірка підтримки AArch64:"
    local gdb_bin
    case "${_PKG_MANAGER}" in
        apt)    gdb_bin="gdb-multiarch" ;;
        pacman) gdb_bin="gdb" ;;
    esac
    "${gdb_bin}" --batch -ex "set architecture aarch64" -ex quit 2>&1 \
        | grep -q "aarch64" \
        && log_ok "AArch64 підтримується" \
        || log_warn "Не вдалося підтвердити підтримку AArch64"

    log_warn "Для remote debug задайте sysroot в IDE або .gdbinit:"
    log_warn "  set sysroot /srv/rpi4-sysroot"
    log_warn "  target remote <rpi-ip>:2345"
}

install_cmake() {
    log_info "=== CMake (перевірка версії) ==="
    if command -v cmake &>/dev/null; then
        local ver
        ver=$(cmake --version | head -1 | grep -oP '\d+\.\d+\.\d+')
        local major minor
        major=$(echo "$ver" | cut -d. -f1)
        minor=$(echo "$ver" | cut -d. -f2)
        if [[ $major -gt 3 ]] || { [[ $major -eq 3 ]] && [[ $minor -ge 28 ]]; }; then
            log_ok "CMake ${ver} (>= 3.28) вже встановлено"
            return
        fi
        log_warn "CMake ${ver} < 3.28. Потрібно оновити."
    fi

    case "${_PKG_MANAGER}" in
        apt)
            log_info "Встановлення CMake через Kitware APT..."
            install_packages ca-certificates gpg wget
            wget -qO- "https://apt.kitware.com/keys/kitware-archive-latest.asc" \
                | gpg --dearmor - > /usr/share/keyrings/kitware-archive-keyring.gpg
            local codename
            codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME}")
            echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] \
https://apt.kitware.com/ubuntu/ ${codename} main" \
                > /etc/apt/sources.list.d/kitware.list
            apt-get update -qq
            install_packages cmake
            ;;
        pacman)
            # Arch завжди має свіжий cmake в extra
            install_packages cmake
            ;;
    esac
    log_info "CMake: $(cmake --version | head -1)"
}

# --- Головна логіка --------------------------------------------------------
main() {
    require_sudo

    local distro
    distro=$(detect_distro)
    log_info "Host система: ${distro}"

    # Визначаємо пакетний менеджер і набір цілей за замовчуванням
    local default_targets=(rpi-arm32 rpi-arm64 ninja cmake gdb)
    case "${distro}" in
        ubuntu:20.04)
            _PKG_MANAGER="apt"
            default_targets+=(native20)
            ;;
        ubuntu:24.04)
            _PKG_MANAGER="apt"
            default_targets+=(native24)
            ;;
        ubuntu:*)
            _PKG_MANAGER="apt"
            log_warn "Ubuntu ${distro#ubuntu:}: перевірте сумісність пакетів."
            ;;
        arch)
            _PKG_MANAGER="pacman"
            default_targets+=(native-arch)
            ;;
        *)
            # Невідомий дистрибутив — пробуємо apt як fallback
            if command -v apt-get &>/dev/null; then
                _PKG_MANAGER="apt"
            elif command -v pacman &>/dev/null; then
                _PKG_MANAGER="pacman"
            else
                log_error "Не вдалося визначити пакетний менеджер."
                exit 1
            fi
            ;;
    esac

    local targets=("$@")
    if [[ ${#targets[@]} -eq 0 ]] || [[ "${targets[0]}" == "all" ]]; then
        targets=("${default_targets[@]}")
    fi

    pkg_update

    for target in "${targets[@]}"; do
        case "${target}" in
            rpi-arm32)    install_rpi_arm32  ;;
            rpi-arm64)    install_rpi_arm64  ;;
            native20)     install_native_gcc_ubuntu20 ;;
            native24)     install_native_gcc_ubuntu24 ;;
            native-arch)  install_native_gcc_arch ;;
            ninja)        install_ninja       ;;
            cmake)        install_cmake       ;;
            gdb)          install_gdb         ;;
            all)          : ;;  # вже оброблено вище
            *)
                log_error "Невідомий варіант: '${target}'"
                echo "Допустимі: all, rpi-arm32, rpi-arm64, native20, native24, native-arch, ninja, cmake, gdb"
                exit 1
                ;;
        esac
    done

    echo ""
    log_ok "=== Встановлення завершено ==="
    echo ""
    echo "Доступні крос-компілятори:"
    for cc in arm-linux-gnueabihf-gcc \
              aarch64-linux-gnu-gcc-12 \
              aarch64-linux-gnu-gcc-13 \
              aarch64-linux-gnu-gcc \
              gcc-10 gcc-13 gcc-14 gcc; do
        if command -v "${cc}" &>/dev/null; then
            printf "  %-35s %s\n" "${cc}" "$(${cc} --version | head -1)"
        fi
    done

    echo ""
    echo "Cross-GDB:"
    for gdb_bin in gdb-multiarch gdb; do
        if command -v "${gdb_bin}" &>/dev/null; then
            printf "  %-35s %s\n" "${gdb_bin}" "$(${gdb_bin} --version | head -1)"
            break
        fi
    done
}

main "$@"
