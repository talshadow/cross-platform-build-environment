# cmake/external/LibEvent.cmake
#
# libevent — бібліотека асинхронної обробки подій (I/O, таймери, сигнали).
# Використовується для побудови мережевих серверів і клієнтів.
# https://libevent.org/
#
# Provides imported targets:
#   libevent::core   — базовий цикл подій (SHARED IMPORTED)
#   libevent::extra  — HTTP, DNS, буфери (SHARED IMPORTED)
#
# Якщо при збірці був доступний OpenSSL::SSL (з нашого external) —
# також стає доступним libevent::openssl.
#
# Опції:
#   USE_SYSTEM_LIBEVENT  — ON: find_package в системі/sysroot
#                          OFF (за замовч.): зібрати через ExternalProject
#
# Кеш-змінні:
#   LIBEVENT_VERSION, LIBEVENT_GIT_REPO

option(USE_SYSTEM_LIBEVENT
    "Використовувати системний libevent замість збірки з джерел"
    OFF)

set(LIBEVENT_VERSION "2.1.12-stable"
    CACHE STRING "Версія libevent для збірки з джерел")

set(LIBEVENT_GIT_REPO
    "https://github.com/libevent/libevent.git"
    CACHE STRING "Git репозиторій libevent")

# ---------------------------------------------------------------------------

set(_libevent_core  "${EXTERNAL_INSTALL_PREFIX}/lib/libevent_core.so")
set(_libevent_extra "${EXTERNAL_INSTALL_PREFIX}/lib/libevent_extra.so")
set(_libevent_inc   "${EXTERNAL_INSTALL_PREFIX}/include")

if(USE_SYSTEM_LIBEVENT)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(Libevent REQUIRED COMPONENTS core extra)
    message(STATUS "[LibEvent] Системна: libevent::core, libevent::extra")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    # LibeventConfig.cmake встановлюється при cmake install → find_package знайде
    # його в EXTERNAL_INSTALL_PREFIX.
    find_package(Libevent QUIET COMPONENTS core
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(Libevent_FOUND)
        message(STATUS "[LibEvent] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")
        # libevent::core і libevent::extra вже створено find_package

    else()
        message(STATUS "[LibEvent] Буде зібрано з джерел (${LIBEVENT_VERSION})")

        # ── OpenSSL: якщо наш external OpenSSL присутній — передаємо явні шляхи.
        # ep_cmake_args вже додає CMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=OFF,
        # тому без явних шляхів libevent не знайде OpenSSL взагалі.
        set(_libevent_ssl_args "-DEVENT__DISABLE_OPENSSL=ON")
        if(TARGET OpenSSL::SSL)
            get_target_property(_ssl_loc    OpenSSL::SSL    IMPORTED_LOCATION)
            get_target_property(_crypto_loc OpenSSL::Crypto IMPORTED_LOCATION)
            if(_ssl_loc AND NOT _ssl_loc MATCHES "NOTFOUND")
                set(_libevent_ssl_args
                    "-DEVENT__DISABLE_OPENSSL=OFF"
                    "-DOPENSSL_ROOT_DIR=${EXTERNAL_INSTALL_PREFIX}"
                    "-DOPENSSL_SSL_LIBRARY=${_ssl_loc}"
                    "-DOPENSSL_CRYPTO_LIBRARY=${_crypto_loc}"
                    "-DOPENSSL_INCLUDE_DIR=${EXTERNAL_INSTALL_PREFIX}/include"
                )
            endif()
            unset(_ssl_loc)
            unset(_crypto_loc)
        endif()

        ep_cmake_args(_libevent_cmake_args
            -DEVENT__DISABLE_TESTS=ON
            -DEVENT__DISABLE_SAMPLES=ON
            -DEVENT__DISABLE_BENCHMARK=ON
            -DEVENT__DISABLE_REGRESS=ON
            -DEVENT__LIBRARY_TYPE=SHARED
            ${_libevent_ssl_args}
        )

        # openssl_ep як залежність (якщо оголошено)
        _ep_collect_deps(_libevent_ep_deps openssl_ep)

        ExternalProject_Add(libevent_ep
            GIT_REPOSITORY  "${LIBEVENT_GIT_REPO}"
            GIT_TAG         "release-${LIBEVENT_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/libevent"
            CMAKE_ARGS      ${_libevent_cmake_args}
            DEPENDS         ${_libevent_ep_deps}
            BUILD_BYPRODUCTS
                "${_libevent_core}"
                "${_libevent_extra}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_library_from_ep(libevent::core  libevent_ep "${_libevent_core}"  "${_libevent_inc}")
        ep_imported_library_from_ep(libevent::extra libevent_ep "${_libevent_extra}" "${_libevent_inc}")
    endif()
endif()

unset(_libevent_core)
unset(_libevent_extra)
unset(_libevent_inc)
