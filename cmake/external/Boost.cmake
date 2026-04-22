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
#   BOOST_USE_GIT     — ON: клонувати git репозиторій (повільніше, ~200 submodules)
#                       OFF (за замовченням): завантажити архів з GitHub Releases
#
# Кеш-змінні:
#   BOOST_VERSION    — версія (git тег без префіксу boost-)
#   BOOST_GIT_REPO   — URL git репозиторію (тільки при BOOST_USE_GIT=ON)

option(USE_SYSTEM_BOOST
    "Використовувати системний Boost (find_package) замість збірки з джерел"
    OFF)

option(BOOST_USE_GIT
    "Завантажувати Boost через git clone (OFF = архів з GitHub Releases)"
    OFF)

set(BOOST_VERSION  "1.90.0"
    CACHE STRING "Версія Boost для збірки з джерел")

set(BOOST_GIT_REPO
    "https://github.com/boostorg/boost.git"
    CACHE STRING "Git репозиторій Boost (використовується тільки при BOOST_USE_GIT=ON)")

# ---------------------------------------------------------------------------

set(_boost_inc     "${EXTERNAL_INSTALL_PREFIX}/include")
set(_boost_lib_po  "${EXTERNAL_INSTALL_PREFIX}/lib/libboost_program_options.so")

if(USE_SYSTEM_BOOST)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(Boost REQUIRED COMPONENTS program_options)
    message(STATUS "[Boost] Системна бібліотека версії ${Boost_VERSION}")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    find_package(Boost QUIET HINTS "${EXTERNAL_INSTALL_PREFIX}" COMPONENTS program_options NO_DEFAULT_PATH)
    if(Boost_FOUND)
        message(STATUS "[Boost] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")
        # find_package(Boost) вже створив Boost::headers та Boost::program_options

    elseif(EXISTS "${_boost_lib_po}")
        ep_imported_interface(Boost::headers "${_boost_inc}")
        ep_imported_library(Boost::program_options "${_boost_lib_po}" "${_boost_inc}")
        target_link_libraries(Boost::program_options INTERFACE Boost::headers)
        message(STATUS "[Boost] Знайдено .so у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[Boost] Буде зібрано з джерел (версія ${BOOST_VERSION})")

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

        # ── Джерело: архів (за замовченням) або git ───────────────────────
        if(BOOST_USE_GIT)
            message(STATUS "[Boost] Джерело: git clone (${BOOST_GIT_REPO})")
            set(_boost_download_args
                GIT_REPOSITORY      "${BOOST_GIT_REPO}"
                GIT_TAG             "boost-${BOOST_VERSION}"
                GIT_SHALLOW         ON
                GIT_SUBMODULES_RECURSE ON
                # Обмежуємо паралелізм клонування submodules щоб уникнути
                # "Unable to read current working directory" при ~200 submodules
                GIT_CONFIG          "submodule.fetchJobs=4"
            )
    else()
        # Офіційний архів з archives.boost.io — набагато швидше ніж git clone.
        # Ім'я файлу використовує підкреслення: boost_1_85_0.tar.gz
        string(REPLACE "." "_" _boost_ver_underscore "${BOOST_VERSION}")
        set(_boost_archive_url
            "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${_boost_ver_underscore}.tar.gz")
        message(STATUS "[Boost] Джерело: архів (${_boost_archive_url})")
        set(_boost_download_args
            URL                 "${_boost_archive_url}"
            DOWNLOAD_EXTRACT_TIMESTAMP ON
        )
    unset(_boost_ver_underscore)
endif()

ExternalProject_Add(boost_ep
    ${_boost_download_args}
    SOURCE_DIR          "${EP_SOURCES_DIR}/boost"
    # bootstrap.sh генерує b2 у вихідній директорії — запускаємо через chdir.
    # BUILD_IN_SOURCE не використовується: b2 отримує --build-dir щоб
    # артефакти компіляції йшли в окрему директорію per-preset і не
    # забруднювали спільний SOURCE_DIR між різними пресетами/toolchain.
    CONFIGURE_COMMAND
    ${CMAKE_COMMAND} -E chdir <SOURCE_DIR>
    <SOURCE_DIR>/bootstrap.sh
    --prefix=${EXTERNAL_INSTALL_PREFIX}
    --with-libraries=program_options
    # b2 build+install (INSTALL_COMMAND залишений порожнім)
    BUILD_COMMAND
    ${CMAKE_COMMAND} -E chdir <SOURCE_DIR>
    <SOURCE_DIR>/b2 install
    --build-dir=<BINARY_DIR>
    --prefix=${EXTERNAL_INSTALL_PREFIX}
    --user-config=${_boost_jam_file}
    toolset=${_boost_toolset}
    ${_boost_target_os}
    link=shared
    runtime-link=shared
    variant=${_boost_variant}
    -j${_EP_NPROC}
    INSTALL_COMMAND   ""
    BUILD_BYPRODUCTS
    "${_boost_lib_po}"
    "${_boost_lib_po_versioned}"
    LOG_DOWNLOAD      ON
    LOG_CONFIGURE     ON
    LOG_BUILD         ON
)

unset(_boost_download_args)

# Оптимізація: якщо SOURCE_DIR вже містить Boost (Jamroot існує),
# попередньо створюємо download stamp щоб уникнути повторного завантаження
# після видалення build-директорії (але збереженні external_sources).
# Для git-mode це не потрібно — ExternalProject сам перевіряє наявність
# репозиторію. Для archive-mode stamp потрібен.
if(NOT BOOST_USE_GIT AND EXISTS "${EP_SOURCES_DIR}/boost/Jamroot")
    set(_boost_stamp_dir "${CMAKE_BINARY_DIR}/boost_ep-prefix/src/boost_ep-stamp")
    set(_boost_dl_stamp  "${_boost_stamp_dir}/boost_ep-download")
    if(NOT EXISTS "${_boost_dl_stamp}")
        file(MAKE_DIRECTORY "${_boost_stamp_dir}")
        file(WRITE "${_boost_dl_stamp}" "")
        message(STATUS "[Boost] Джерела вже є у ${EP_SOURCES_DIR}/boost — download stamp створено (пропускаємо завантаження)")
    endif()
    unset(_boost_stamp_dir)
    unset(_boost_dl_stamp)
endif()

ep_imported_interface_from_ep(Boost::headers boost_ep "${_boost_inc}")
ep_imported_library_from_ep(
    Boost::program_options boost_ep "${_boost_lib_po}" "${_boost_inc}")
target_link_libraries(Boost::program_options
    INTERFACE Boost::headers)
ep_track_cmake_file(boost_ep "${CMAKE_CURRENT_LIST_FILE}")
endif()
endif()

unset(_boost_inc)
unset(_boost_lib_po)
