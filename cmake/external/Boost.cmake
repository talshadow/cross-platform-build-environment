# cmake/external/Boost.cmake
#
# Збирає або знаходить Boost.
# Компілований компонент: program_options
# Header-only: Boost::headers (всі заголовкові компоненти Boost)
#
# Provides imported targets:
#   Boost::headers          — INTERFACE IMPORTED (header-only)
#   Boost::program_options  — SHARED IMPORTED
#
# Крос-компіляція: генерує user-config.jam з крос-компілятором для b2.
# bootstrap.sh завжди виконується HOST компілятором (будує інструмент b2).
#
# Опції:
#   USE_SYSTEM_BOOST  — ON: find_package в системі/sysroot
#                       OFF (за замовченням): зібрати через ExternalProject
#
# Кеш-змінні:
#   BOOST_VERSION    — версія для збірки
#   BOOST_URL        — URL архіву
#   BOOST_URL_HASH   — SHA256 хеш (порожньо = не перевіряти)

option(USE_SYSTEM_BOOST
    "Використовувати системний Boost (find_package) замість збірки з джерел"
    OFF)

set(BOOST_VERSION  "1.85.0"
    CACHE STRING "Версія Boost для збірки з джерел")

# Перетворюємо "1.85.0" -> "1_85_0" для URL
string(REPLACE "." "_" _boost_ver_underscored "${BOOST_VERSION}")

set(BOOST_URL
    "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${_boost_ver_underscored}.tar.gz"
    CACHE STRING "URL архіву Boost")

set(BOOST_URL_HASH ""
    CACHE STRING "SHA256 хеш архіву Boost (порожньо = не перевіряти)")

# ---------------------------------------------------------------------------

set(_boost_inc     "${EXTERNAL_INSTALL_PREFIX}/include")
set(_boost_lib_po  "${EXTERNAL_INSTALL_PREFIX}/lib/libboost_program_options.so")
set(_boost_ver_hdr "${EXTERNAL_INSTALL_PREFIX}/include/boost/version.hpp")

if(USE_SYSTEM_BOOST)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(Boost REQUIRED COMPONENTS program_options)
    message(STATUS "[Boost] Системна бібліотека версії ${Boost_VERSION}")

else()
    # ── Збірка через ExternalProject ────────────────────────────────────────
    if(EXISTS "${_boost_lib_po}" AND EXISTS "${_boost_ver_hdr}")
        message(STATUS "[Boost] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

        ep_imported_interface(Boost::headers "${_boost_inc}")
        ep_imported_library(Boost::program_options "${_boost_lib_po}" "${_boost_inc}")
        target_link_libraries(Boost::program_options
            INTERFACE Boost::headers)

    else()
        message(STATUS "[Boost] Буде зібрано з джерел (версія ${BOOST_VERSION})")

        set(_boost_hash_arg "")
        if(BOOST_URL_HASH)
            set(_boost_hash_arg URL_HASH "SHA256=${BOOST_URL_HASH}")
        endif()

        # ── Генеруємо user-config.jam для b2 ──────────────────────────────
        # При крос-компіляції bootstrap.sh будує b2 host-компілятором,
        # а b2 використовує jam-файл для крос-компілятора.
        set(_boost_jam_file "${CMAKE_BINARY_DIR}/_ep_cfg/boost-user-config.jam")
        file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/_ep_cfg")

        if(CMAKE_CROSSCOMPILING AND CMAKE_CXX_COMPILER)
            # "cross" — коротке фіксоване ім'я версії для b2.
            # Складні імена (cross-arm-linux-gnueabihf) можуть плутати парсер b2
            # коли він розбиває toolset=gcc-VERSION по дефісу.
            set(_boost_toolset_name "cross")

            file(WRITE "${_boost_jam_file}"
                "using gcc : ${_boost_toolset_name} : ${CMAKE_CXX_COMPILER} ;\n")
            set(_boost_toolset "gcc-${_boost_toolset_name}")

            # Цільова ОС для b2
            set(_boost_target_os "target-os=linux")
        else()
            file(WRITE "${_boost_jam_file}"
                "using gcc : : ${CMAKE_CXX_COMPILER} ;\n")
            set(_boost_toolset "gcc")
            set(_boost_target_os "")
        endif()

        # ── Variant для b2 ────────────────────────────────────────────────
        # Generator expressions ($<CONFIG:...>) не підтримуються в ExternalProject
        # BUILD_COMMAND — використовуємо звичайний if/else
        if(CMAKE_BUILD_TYPE STREQUAL "Debug")
            set(_boost_variant "debug")
        else()
            set(_boost_variant "release")
        endif()

        # ── BYPRODUCTS з версованим суфіксом ──────────────────────────────
        # Boost іменує .so як libboost_xxx.so.<major>.<minor>.<patch>
        # Додаємо обидва — для Ninja правильне відстеження залежностей
        set(_boost_lib_po_versioned
            "${EXTERNAL_INSTALL_PREFIX}/lib/libboost_program_options.so.${BOOST_VERSION}")

        ExternalProject_Add(boost_ep
            URL              "${BOOST_URL}"
            ${_boost_hash_arg}
            # bootstrap.sh завжди виконується на HOST (будує b2)
            CONFIGURE_COMMAND <SOURCE_DIR>/bootstrap.sh
                --prefix=${EXTERNAL_INSTALL_PREFIX}
                --with-libraries=program_options
            # b2 build+install (INSTALL_COMMAND залишений порожнім)
            BUILD_COMMAND     <SOURCE_DIR>/b2 install
                --prefix=${EXTERNAL_INSTALL_PREFIX}
                --user-config=${_boost_jam_file}
                toolset=${_boost_toolset}
                ${_boost_target_os}
                link=shared
                runtime-link=shared
                variant=${_boost_variant}
                -j${_EP_NPROC}
            INSTALL_COMMAND   ""
            BUILD_IN_SOURCE   ON
            BUILD_BYPRODUCTS
                "${_boost_lib_po}"
                "${_boost_lib_po_versioned}"
            LOG_DOWNLOAD      ON
            LOG_CONFIGURE     ON
            LOG_BUILD         ON
        )

        ep_imported_interface_from_ep(Boost::headers boost_ep "${_boost_inc}")
        ep_imported_library_from_ep(
            Boost::program_options boost_ep "${_boost_lib_po}" "${_boost_inc}")
        target_link_libraries(Boost::program_options
            INTERFACE Boost::headers)
    endif()
endif()

unset(_boost_inc)
unset(_boost_lib_po)
unset(_boost_ver_hdr)
unset(_boost_ver_underscored)
