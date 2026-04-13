# cmake/external/LibPng.cmake
#
# Збирає або знаходить libpng.
#
# Provides imported target:
#   PNG::PNG  — SHARED IMPORTED (або INTERFACE при USE_SYSTEM_LIBPNG=ON)
#
# Опції:
#   USE_SYSTEM_LIBPNG  — ON: find_package в системі/sysroot
#                        OFF (за замовченням): зібрати через ExternalProject
#
# Кеш-змінні:
#   LIBPNG_VERSION    — версія для збірки
#   LIBPNG_URL        — URL архіву
#   LIBPNG_URL_HASH   — SHA256 хеш (порожньо = не перевіряти)

option(USE_SYSTEM_LIBPNG
    "Використовувати системний libpng (find_package) замість збірки з джерел"
    OFF)

set(LIBPNG_VERSION  "1.6.43"
    CACHE STRING "Версія libpng для збірки з джерел")

set(LIBPNG_URL
    "https://downloads.sourceforge.net/project/libpng/libpng16/${LIBPNG_VERSION}/libpng-${LIBPNG_VERSION}.tar.gz"
    CACHE STRING "URL архіву libpng")

set(LIBPNG_URL_HASH ""
    CACHE STRING "SHA256 хеш архіву libpng (порожньо = не перевіряти)")

# ---------------------------------------------------------------------------

set(_png_lib "${EXTERNAL_INSTALL_PREFIX}/lib/libpng.so")
set(_png_inc "${EXTERNAL_INSTALL_PREFIX}/include")
set(_png_hdr "${EXTERNAL_INSTALL_PREFIX}/include/png.h")

if(USE_SYSTEM_LIBPNG)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    # При крос-компіляції toolchain вже налаштовує CMAKE_FIND_ROOT_PATH на
    # sysroot, тому find_package автоматично шукає в правильному місці.
    find_package(PNG REQUIRED)
    message(STATUS "[LibPng] Системна бібліотека: ${PNG_LIBRARIES}")

else()
    # ── Збірка через ExternalProject ────────────────────────────────────────
    # libpng встановлює libpng.so (симлінк) та libpng16.so (версований симлінк)
    set(_png_lib16 "${EXTERNAL_INSTALL_PREFIX}/lib/libpng16.so")
    if((EXISTS "${_png_lib}" OR EXISTS "${_png_lib16}") AND EXISTS "${_png_hdr}")
        # Вже встановлено в EXTERNAL_INSTALL_PREFIX — просто створюємо target
        message(STATUS "[LibPng] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")

        # Вибираємо файл що існує (libpng.so або libpng16.so)
        if(EXISTS "${_png_lib}")
            set(_png_actual_lib "${_png_lib}")
        else()
            set(_png_actual_lib "${_png_lib16}")
        endif()

        ep_imported_library(PNG::PNG "${_png_actual_lib}" "${_png_inc}")

    else()
        # Треба зібрати
        message(STATUS "[LibPng] Буде зібрано з джерел (версія ${LIBPNG_VERSION})")

        set(_png_hash_arg "")
        if(LIBPNG_URL_HASH)
            set(_png_hash_arg URL_HASH "SHA256=${LIBPNG_URL_HASH}")
        endif()

        ep_cmake_args(_png_cmake_args
            -DPNG_SHARED=ON
            -DPNG_STATIC=OFF
            -DPNG_TESTS=OFF
            -DPNG_TOOLS=OFF
        )

        ExternalProject_Add(libpng_ep
            URL             "${LIBPNG_URL}"
            ${_png_hash_arg}
            CMAKE_ARGS      ${_png_cmake_args}
            BUILD_BYPRODUCTS "${_png_lib}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        # Створюємо imported target з майбутніми шляхами.
        # При крос-компіляції ці файли є target-бінарниками (ARM/ARM64).
        ep_imported_library_from_ep(PNG::PNG libpng_ep "${_png_lib}" "${_png_inc}")
    endif()
endif()

unset(_png_lib)
unset(_png_inc)
unset(_png_hdr)
