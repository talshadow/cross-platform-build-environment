# cmake/install_project.cmake
#
# CMake -P скрипт кастомної інсталяції головного виконуваного файлу.
# Аналізує EP/toolchain залежності через ep_check_binary_deps, копіює
# артефакти за GNUInstallDirs та, опційно, стрипує debug-інформацію.
#
# Виклик:
#   cmake
#     -DBINARY_FILE=<path>
#     -DINSTALL_PREFIX=<path>
#     -DEXTERNAL_INSTALL_PREFIX=<path>
#     -DCMAKE_MODULE_PATH=<path>
#     -DCMAKE_C_COMPILER=<path>          # для пошуку toolchain libs
#     -DCMAKE_READELF=<path>             # readelf (якщо не в PATH)
#     -DCMAKE_STRIP=<path>               # strip (обов'язково якщо DO_STRIP=ON)
#     -DDO_STRIP=<ON|OFF>
#     -DINSTALL_BINDIR=<rel>             # за замовч. "bin"
#     -DINSTALL_LIBDIR=<rel>             # за замовч. "lib"
#     -P cmake/install_project.cmake

cmake_minimum_required(VERSION 3.28)

# ---------------------------------------------------------------------------
# Валідація обов'язкових параметрів
# ---------------------------------------------------------------------------
foreach(_req BINARY_FILE INSTALL_PREFIX EXTERNAL_INSTALL_PREFIX CMAKE_MODULE_PATH)
    if(NOT DEFINED ${_req} OR "${${_req}}" STREQUAL "")
        message(FATAL_ERROR "[install_project] Не передано обов'язковий параметр: -D${_req}=...")
    endif()
endforeach()

if(NOT EXISTS "${BINARY_FILE}")
    message(FATAL_ERROR "[install_project] Виконуваний файл не знайдено: ${BINARY_FILE}")
endif()

# Директорії за GNUInstallDirs (bin/lib за замовч.)
if(NOT DEFINED INSTALL_BINDIR OR INSTALL_BINDIR STREQUAL "")
    set(INSTALL_BINDIR "bin")
endif()
if(NOT DEFINED INSTALL_LIBDIR OR INSTALL_LIBDIR STREQUAL "")
    set(INSTALL_LIBDIR "lib")
endif()

set(_bin_dir "${INSTALL_PREFIX}/${INSTALL_BINDIR}")
set(_lib_dir "${INSTALL_PREFIX}/${INSTALL_LIBDIR}")

# ---------------------------------------------------------------------------
# Збір залежностей через ep_check_binary_deps
# ---------------------------------------------------------------------------
include(BinaryDeps)

message(STATUS "[install_project] Аналіз залежностей: ${BINARY_FILE}")
ep_check_binary_deps("${BINARY_FILE}" _deploy_libs)

list(LENGTH _deploy_libs _n_libs)

# ---------------------------------------------------------------------------
# Копіювання артефактів
# ---------------------------------------------------------------------------
file(MAKE_DIRECTORY "${_bin_dir}" "${_lib_dir}")

get_filename_component(_binary_name "${BINARY_FILE}" NAME)

# -- Виконуваний файл
message(STATUS "[install_project] bin/ ← ${_binary_name}")
file(COPY "${BINARY_FILE}" DESTINATION "${_bin_dir}")
file(CHMOD "${_bin_dir}/${_binary_name}"
    FILE_PERMISSIONS
        OWNER_READ OWNER_WRITE OWNER_EXECUTE
        GROUP_READ GROUP_EXECUTE
        WORLD_READ WORLD_EXECUTE
)

# -- EP + toolchain бібліотеки
if(_n_libs GREATER 0)
    message(STATUS "[install_project] lib/ ← ${_n_libs} бібліотек(и)")
    foreach(_lib IN LISTS _deploy_libs)
        file(INSTALL "${_lib}"
            DESTINATION "${_lib_dir}"
            TYPE SHARED_LIBRARY
            FOLLOW_SYMLINK_CHAIN
        )
    endforeach()
else()
    message(STATUS "[install_project] Зовнішніх бібліотек не знайдено")
endif()

# ---------------------------------------------------------------------------
# Стрипування (DO_STRIP=ON)
# ---------------------------------------------------------------------------
if(DO_STRIP)
    if(NOT CMAKE_STRIP)
        message(WARNING "[install_project] DO_STRIP=ON, але CMAKE_STRIP не передано — пропускаємо")
    else()
        message(STATUS "[install_project] Стрипування (${CMAKE_STRIP})")

        # Виконуваний: --strip-all (видалити всі символи)
        set(_installed_bin "${_bin_dir}/${_binary_name}")
        execute_process(
            COMMAND "${CMAKE_STRIP}" --strip-all "${_installed_bin}"
            RESULT_VARIABLE _res
        )
        if(NOT _res EQUAL 0)
            message(WARNING "[install_project] strip --strip-all завершився з кодом ${_res}: ${_installed_bin}")
        endif()

        # Shared libs: --strip-debug (зберегти таблицю символів для dlopen)
        file(GLOB_RECURSE _installed_libs
            LIST_DIRECTORIES false
            "${_lib_dir}/*.so*"
        )
        foreach(_lib IN LISTS _installed_libs)
            if(NOT IS_SYMLINK "${_lib}")
                execute_process(
                    COMMAND "${CMAKE_STRIP}" --strip-debug "${_lib}"
                    RESULT_VARIABLE _res
                )
                if(NOT _res EQUAL 0)
                    message(WARNING "[install_project] strip --strip-debug завершився з кодом ${_res}: ${_lib}")
                endif()
            endif()
        endforeach()

        message(STATUS "[install_project] Стрипування завершено")
    endif()
endif()

# ---------------------------------------------------------------------------
# Runtime ресурси (плагіни, конфіги, data-файли)
#
# Копіюються ПІСЛЯ strip EP-libs — IPA .so тоді ще не існують у lib/
# і тому не потрапляють у попередній strip-цикл (lib/*.so*).
# ---------------------------------------------------------------------------
set(_rt_dirs_copied 0)
set(_rt_resigned    0)

if(DEFINED RUNTIME_RESOURCES_FILE AND EXISTS "${RUNTIME_RESOURCES_FILE}")
    include("${RUNTIME_RESOURCES_FILE}")
else()
    set(EP_RT_COUNT 0)
endif()

if(EP_RT_COUNT GREATER 0)
    message(STATUS "[install_project] Runtime ресурси (${EP_RT_COUNT} директорій):")
    math(EXPR _rt_last "${EP_RT_COUNT} - 1")
    foreach(_i RANGE 0 ${_rt_last})
        set(_rt_src "${EP_RT_SRC_${_i}}")
        set(_rt_dst "${INSTALL_PREFIX}/${EP_RT_DST_${_i}}")
        if(EXISTS "${_rt_src}")
            get_filename_component(_rt_dir_name "${_rt_src}" NAME)
            file(COPY "${_rt_src}" DESTINATION "${_rt_dst}")
            message(STATUS "[install_project]   ${EP_RT_DST_${_i}}/${_rt_dir_name}/")
            math(EXPR _rt_dirs_copied "${_rt_dirs_copied} + 1")
        else()
            message(WARNING "[install_project] Runtime ресурс не знайдено (EP ще не зібрано?): ${_rt_src}")
        endif()
    endforeach()
endif()

# ---------------------------------------------------------------------------
# Strip + ре-підпис IPA-модулів
#
# Виконується лише якщо DO_STRIP=ON і для директорії задано SIGN_KEY.
# IPA .so мають embedded-підпис (SHA256 + openssl), strip без ре-підпису
# інвалідує підпис і libcamera відмовляє завантажувати плагін.
# Якщо SIGN_KEY не задано — NO_STRIP директорії не стріпуються зовсім.
# ---------------------------------------------------------------------------
if(DO_STRIP AND EP_RT_COUNT GREATER 0)
    find_program(_rt_openssl openssl)
    math(EXPR _rt_last "${EP_RT_COUNT} - 1")
    foreach(_i RANGE 0 ${_rt_last})
        if(NOT EP_RT_NO_STRIP_${_i})
            continue()
        endif()
        set(_rt_key "${EP_RT_SIGN_KEY_${_i}}")
        if(NOT _rt_key OR NOT EXISTS "${_rt_key}")
            continue()
        endif()
        if(NOT _rt_openssl)
            message(WARNING "[install_project] openssl не знайдено — ре-підпис IPA пропущено")
            break()
        endif()

        set(_rt_src "${EP_RT_SRC_${_i}}")
        get_filename_component(_rt_dir_name "${_rt_src}" NAME)
        set(_rt_installed_dir "${INSTALL_PREFIX}/${EP_RT_DST_${_i}}/${_rt_dir_name}")
        if(NOT EXISTS "${_rt_installed_dir}")
            continue()
        endif()

        file(GLOB _rt_ipa_modules "${_rt_installed_dir}/ipa_*.so")
        foreach(_mod IN LISTS _rt_ipa_modules)
            execute_process(
                COMMAND "${CMAKE_STRIP}" --strip-debug "${_mod}"
                RESULT_VARIABLE _res)
            if(NOT _res EQUAL 0)
                message(WARNING "[install_project] strip провалено: ${_mod}")
                continue()
            endif()
            execute_process(
                COMMAND "${_rt_openssl}" dgst -sha256
                    -sign "${_rt_key}" -out "${_mod}.sign" "${_mod}"
                RESULT_VARIABLE _sign_res)
            if(NOT _sign_res EQUAL 0)
                message(WARNING "[install_project] ре-підпис провалено: ${_mod}")
            else()
                get_filename_component(_mod_name "${_mod}" NAME)
                message(STATUS "[install_project]   resign: ${_mod_name}")
                math(EXPR _rt_resigned "${_rt_resigned} + 1")
            endif()
        endforeach()
    endforeach()
endif()

# ---------------------------------------------------------------------------
# Підсумок
# ---------------------------------------------------------------------------
message(STATUS "")
message(STATUS "[install_project] ─────────────────────────────────────────")
message(STATUS "[install_project] Інсталяція завершена:")
message(STATUS "[install_project]   Префікс:       ${INSTALL_PREFIX}")
message(STATUS "[install_project]   Виконуваний:   ${INSTALL_BINDIR}/${_binary_name}")
message(STATUS "[install_project]   Бібліотеки:    ${_n_libs} у ${INSTALL_LIBDIR}/")
if(_rt_dirs_copied GREATER 0)
    message(STATUS "[install_project]   Runtime dirs:  ${_rt_dirs_copied} скопійовано")
endif()
if(DO_STRIP)
    message(STATUS "[install_project]   Стрипований:   YES (--strip-all bin, --strip-debug libs)")
    if(_rt_resigned GREATER 0)
        message(STATUS "[install_project]   IPA ре-підпис: ${_rt_resigned} модулів")
    endif()
endif()
message(STATUS "")
