# cmake/external/OpenSSL.cmake
#
# Збирає або знаходить OpenSSL (не CMake-проєкт, використовує Configure/make).
#
# Provides imported targets:
#   OpenSSL::SSL     — SHARED IMPORTED
#   OpenSSL::Crypto  — SHARED IMPORTED
#
# Крос-компіляція:
#   Визначає платформу OpenSSL з CMAKE_SYSTEM_PROCESSOR.
#   Для крос-компілятора виводить префікс з CMAKE_C_COMPILER.
#
# Асемблер:
#   Оптимізації на базі асемблера увімкнені за замовчуванням (no-asm НЕ передається).
#   Для крос-збірки (arm/aarch64): perlasm генерує asm для target-архітектури,
#     компілюється cross-компілятором через --cross-compile-prefix.
#   Для нативної x86_64: OpenSSL може використовувати NASM для AES-NI/SHA-NI —
#     якщо NASM відсутній, використовується gas-backend (трохи менш оптимальний).
#
# Відключені небезпечні/застарілі алгоритми (як Ubuntu):
#   no-ssl3, no-ssl3-method — SSLv3 (POODLE)
#   no-idea                 — IDEA (патентний)
#   no-rc5                  — RC5 (патентний)
#   no-mdc2                 — MDC2 (патентний)
#
# Увімкнені розширення (як Ubuntu):
#   enable-rfc3779 — X.509 IP/AS-number extensions
#   enable-ktls    — kernel TLS (Linux ≥ 4.17; runtime-fallback якщо ядро не підтримує)
#
# Опції:
#   USE_SYSTEM_OPENSSL  — ON: find_package в системі/sysroot
#                         OFF (за замовченням): зібрати через ExternalProject
#
# Кеш-змінні:
#   OPENSSL_VERSION    — версія (git тег без префіксу openssl-)
#   OPENSSL_GIT_REPO   — URL git репозиторію

option(USE_SYSTEM_OPENSSL
    "Використовувати системний OpenSSL (find_package) замість збірки з джерел"
    OFF)

set(OPENSSL_VERSION  "3.3.1"
    CACHE STRING "Версія OpenSSL для збірки з джерел")

set(OPENSSL_GIT_REPO
    "https://github.com/openssl/openssl.git"
    CACHE STRING "Git репозиторій OpenSSL")

# ---------------------------------------------------------------------------

# OpenSSL 3.x: soname = libssl.so.3, libcrypto.so.3
set(_ssl_lib3    "${EXTERNAL_INSTALL_PREFIX}/lib/libssl.so.3")
set(_crypto_lib3 "${EXTERNAL_INSTALL_PREFIX}/lib/libcrypto.so.3")
set(_ssl_inc     "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_OPENSSL)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(OpenSSL REQUIRED)
    message(STATUS "[OpenSSL] Системна бібліотека версії ${OPENSSL_VERSION_STRING}")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(OpenSSL QUIET HINTS "${EXTERNAL_INSTALL_PREFIX}" NO_DEFAULT_PATH)
    if(OPENSSL_FOUND)
        message(STATUS "[OpenSSL] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")
        # find_package(OpenSSL) вже створив OpenSSL::SSL та OpenSSL::Crypto

    else()
        message(STATUS "[OpenSSL] Буде зібрано з джерел (версія ${OPENSSL_VERSION})")

        # ── Визначаємо платформу OpenSSL ──────────────────────────────────
        # OpenSSL Configure не розуміє CMAKE_SYSTEM_PROCESSOR напряму —
        # потрібен власний рядок платформи.
        if(CMAKE_CROSSCOMPILING)
            string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _proc)

            if(_proc MATCHES "aarch64|arm64")
                set(_ssl_platform "linux-aarch64")
            elseif(_proc MATCHES "armv7|arm")
                # OpenSSL використовує "armv4" як загальний ARM (не ARMv4, а ARM generic)
                set(_ssl_platform "linux-armv4")
            elseif(_proc MATCHES "x86_64|amd64")
                set(_ssl_platform "linux-x86_64")
            elseif(_proc MATCHES "x86|i[3-6]86")
                set(_ssl_platform "linux-x86")
            else()
                set(_ssl_platform "linux-generic64")
                message(WARNING "[OpenSSL] Невідома архітектура '${_proc}', використовується linux-generic64")
            endif()

            # Визначаємо cross-compile-prefix з назви компілятора.
            # Очікуємо формат: <triple>-gcc[suffix]  напр. arm-linux-gnueabihf-gcc
            # Результат:  arm-linux-gnueabihf-
            # Якщо компілятор не має triple-префіксу (просто "gcc") — залишаємо порожнім.
            get_filename_component(_cc_name "${CMAKE_C_COMPILER}" NAME)
            string(REGEX REPLACE "-gcc.*$" "-" _ssl_cross_prefix "${_cc_name}")
            # Перевіряємо що результат завершується на "-" (ознака реального triple)
            if(NOT _ssl_cross_prefix MATCHES "-$")
                set(_ssl_cross_prefix "")
            endif()

        else()
            # Нативна збірка
            set(_ssl_cross_prefix "")
            string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _proc)
            if(_proc MATCHES "x86_64|amd64")
                set(_ssl_platform "linux-x86_64")
            elseif(_proc MATCHES "aarch64|arm64")
                set(_ssl_platform "linux-aarch64")
            elseif(_proc MATCHES "arm")
                set(_ssl_platform "linux-armv4")
            else()
                set(_ssl_platform "linux-generic64")
            endif()
        endif()

        message(STATUS "[OpenSSL] Платформа: ${_ssl_platform}, cross-prefix: '${_ssl_cross_prefix}'")

        # ── GNU Make — OpenSSL Configure генерує Makefile, не підтримує Ninja ──
        # CMAKE_MAKE_PROGRAM може бути ninja при відповідному генераторі —
        # тому шукаємо make/gmake явно.
        find_program(_ssl_make
            NAMES make gmake mingw32-make nmake
            REQUIRED
            DOC "Make для збірки OpenSSL: make/gmake (Linux), mingw32-make (MinGW), nmake (MSVC). Ninja не підтримується.")
        message(STATUS "[OpenSSL] Make: ${_ssl_make}")

        # ── NASM (тільки x86/x86_64 нативна збірка) ──────────────────────
        # OpenSSL використовує NASM для AES-NI/SHA-NI оптимізацій на x86_64.
        # Якщо NASM відсутній — OpenSSL автоматично перемикається на gas backend
        # (perlasm .s), що трохи повільніше але коректно.
        # При крос-компіляції NASM не потрібен: perlasm генерує arm/aarch64 asm,
        # який компілюється через cross-compiler без NASM.
        if(NOT CMAKE_CROSSCOMPILING AND _ssl_platform MATCHES "x86")
            find_program(_ssl_nasm NAMES nasm)
            if(_ssl_nasm)
                message(STATUS "[OpenSSL] NASM знайдено (${_ssl_nasm}) — AES-NI/SHA-NI оптимізації увімкнено")
            else()
                message(STATUS "[OpenSSL] NASM не знайдено — використовується gas backend (менш оптимально).\n"
                    "  Для AES-NI/SHA-NI оптимізацій встановіть NASM:\n"
                    "    Ubuntu/Debian : sudo apt install nasm\n"
                    "    Arch/CachyOS  : sudo pacman -S nasm")
            endif()
            unset(_ssl_nasm)
        endif()

        # ── Формуємо аргументи для Configure ──────────────────────────────
        set(_ssl_configure_cmd
            <SOURCE_DIR>/Configure
            ${_ssl_platform}
            --prefix=${EXTERNAL_INSTALL_PREFIX}
            --libdir=lib
            shared
            no-tests
            no-docs
            # Відключаємо застарілі/небезпечні алгоритми (як Ubuntu)
            no-ssl3             # SSLv3 (POODLE attack)
            no-ssl3-method      # SSLv3_method() API
            no-idea             # IDEA cipher (патентний)
            no-rc5              # RC5 cipher (патентний)
            no-mdc2             # MDC2 hash (патентний)
            # Увімкнені розширення (як Ubuntu)
            enable-rfc3779      # X.509 IP address / AS number extensions
            enable-ktls         # kernel TLS (Linux ≥ 4.17; safe runtime-fallback)
        )

        if(_ssl_cross_prefix)
            list(APPEND _ssl_configure_cmd
                "--cross-compile-prefix=${_ssl_cross_prefix}")
        endif()

        if(CMAKE_SYSROOT)
            list(APPEND _ssl_configure_cmd "--sysroot=${CMAKE_SYSROOT}")
        endif()

        ExternalProject_Add(openssl_ep
            GIT_REPOSITORY   "${OPENSSL_GIT_REPO}"
            GIT_TAG          "openssl-${OPENSSL_VERSION}"
            GIT_SHALLOW      ON
            SOURCE_DIR       "${EP_SOURCES_DIR}/openssl"
            CONFIGURE_COMMAND ${_ssl_configure_cmd}
            BUILD_COMMAND     ${_ssl_make} -j${_EP_NPROC}
            # install_sw: тільки бібліотеки/заголовки, без man-сторінок
            INSTALL_COMMAND   ${_ssl_make} install_sw
            BUILD_IN_SOURCE   ON
            # Тільки версовані файли — симлінки (.so) не є byproducts для Ninja
            BUILD_BYPRODUCTS
                "${_ssl_lib3}"
                "${_crypto_lib3}"
            LOG_DOWNLOAD      ON
            LOG_CONFIGURE     ON
            LOG_BUILD         ON
            LOG_INSTALL       ON
        )

        ep_imported_library_from_ep(OpenSSL::Crypto openssl_ep "${_crypto_lib3}" "${_ssl_inc}")
        ep_imported_library_from_ep(OpenSSL::SSL    openssl_ep "${_ssl_lib3}"    "${_ssl_inc}")
        target_link_libraries(OpenSSL::SSL INTERFACE OpenSSL::Crypto)

        unset(_ssl_make)
    endif()
endif()

unset(_ssl_lib3)
unset(_crypto_lib3)
unset(_ssl_inc)
