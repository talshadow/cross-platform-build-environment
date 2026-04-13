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
# Опції:
#   USE_SYSTEM_OPENSSL  — ON: find_package в системі/sysroot
#                         OFF (за замовченням): зібрати через ExternalProject
#
# Кеш-змінні:
#   OPENSSL_VERSION    — версія для збірки
#   OPENSSL_URL        — URL архіву
#   OPENSSL_URL_HASH   — SHA256 хеш (порожньо = не перевіряти)

option(USE_SYSTEM_OPENSSL
    "Використовувати системний OpenSSL (find_package) замість збірки з джерел"
    OFF)

set(OPENSSL_VERSION  "3.3.1"
    CACHE STRING "Версія OpenSSL для збірки з джерел")

set(OPENSSL_URL
    "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
    CACHE STRING "URL архіву OpenSSL")

set(OPENSSL_URL_HASH ""
    CACHE STRING "SHA256 хеш архіву OpenSSL (порожньо = не перевіряти)")

# ---------------------------------------------------------------------------

# OpenSSL 3.x: soname = libssl.so.3, libcrypto.so.3
set(_ssl_lib     "${EXTERNAL_INSTALL_PREFIX}/lib/libssl.so")
set(_crypto_lib  "${EXTERNAL_INSTALL_PREFIX}/lib/libcrypto.so")
set(_ssl_lib3    "${EXTERNAL_INSTALL_PREFIX}/lib/libssl.so.3")
set(_crypto_lib3 "${EXTERNAL_INSTALL_PREFIX}/lib/libcrypto.so.3")
set(_ssl_inc     "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_OPENSSL)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(OpenSSL REQUIRED)
    message(STATUS "[OpenSSL] Системна бібліотека версії ${OPENSSL_VERSION_STRING}")

else()
    # ── Збірка через ExternalProject ────────────────────────────────────────
    if(EXISTS "${_ssl_lib3}" AND EXISTS "${_crypto_lib3}")
        message(STATUS "[OpenSSL] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

        ep_imported_library(OpenSSL::Crypto "${_crypto_lib3}" "${_ssl_inc}")
        ep_imported_library(OpenSSL::SSL    "${_ssl_lib3}"    "${_ssl_inc}")
        target_link_libraries(OpenSSL::SSL INTERFACE OpenSSL::Crypto)

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

        # ── Формуємо аргументи для Configure ──────────────────────────────
        set(_ssl_configure_cmd
            <SOURCE_DIR>/Configure
            ${_ssl_platform}
            --prefix=${EXTERNAL_INSTALL_PREFIX}
            --libdir=lib
            shared
            no-tests
            no-docs
        )

        if(_ssl_cross_prefix)
            list(APPEND _ssl_configure_cmd
                "--cross-compile-prefix=${_ssl_cross_prefix}")
        endif()

        if(CMAKE_SYSROOT)
            list(APPEND _ssl_configure_cmd "--sysroot=${CMAKE_SYSROOT}")
        endif()

        set(_ssl_hash_arg "")
        if(OPENSSL_URL_HASH)
            set(_ssl_hash_arg URL_HASH "SHA256=${OPENSSL_URL_HASH}")
        endif()

        ExternalProject_Add(openssl_ep
            URL              "${OPENSSL_URL}"
            ${_ssl_hash_arg}
            CONFIGURE_COMMAND ${_ssl_configure_cmd}
            BUILD_COMMAND     ${CMAKE_MAKE_PROGRAM} -j${_EP_NPROC}
            # install_sw: тільки бібліотеки/заголовки, без man-сторінок
            INSTALL_COMMAND   ${CMAKE_MAKE_PROGRAM} install_sw
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
    endif()
endif()

unset(_ssl_lib)
unset(_crypto_lib)
unset(_ssl_lib3)
unset(_crypto_lib3)
unset(_ssl_inc)
