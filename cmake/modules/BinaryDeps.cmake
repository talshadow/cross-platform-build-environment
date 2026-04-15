# cmake/modules/BinaryDeps.cmake
#
# ep_check_binary_deps(<binary_path>)
#
# Рекурсивно знаходить всі залежності бінарного файлу на динамічні
# бібліотеки та класифікує їх за джерелом:
#
#   [EP]       — з EXTERNAL_INSTALL_PREFIX  ← рекурсія продовжується
#   [TOOLCHAIN]— з директорії компілятора   ← рекурсія продовжується
#   [SYSROOT]  — з CMAKE_SYSROOT            ← листовий вузол
#   [SYSTEM]   — системна бібліотека хоста  ← листовий вузол
#   [MISSING]  — не знайдено жодним шляхом  ← попередження
#
# Рекурсія йде вглиб по EP та TOOLCHAIN бібліотеках до тих пір, поки
# не вийде за їхні межі (SYSROOT/SYSTEM) або не зустріне вже відвіданий
# вузол (захист від циклів).
#
# Використання:
#   include(BinaryDeps)
#   ep_check_binary_deps("/path/to/mybinary")
#   ep_check_binary_deps($<TARGET_FILE:my_target>)
#
# Залежить від:
#   CMAKE_READELF           — встановлюється cmake (підтримує cross-build)
#   EXTERNAL_INSTALL_PREFIX — з cmake/external/Common.cmake
#   CMAKE_SYSROOT           — з toolchain файлу (опційно)
#   CMAKE_C_COMPILER        — для пошуку директорії тулчейна

# ---------------------------------------------------------------------------
# Внутрішній хелпер: будує список директорій для пошуку бібліотек
# ---------------------------------------------------------------------------
function(_ep_binarydeps_build_search_dirs)
    if(DEFINED _EP_BINARYDEPS_SEARCH_DIRS_BUILT)
        return()
    endif()

    # ── EP ──────────────────────────────────────────────────────────────────
    set(_ep_dirs "")
    if(DEFINED EXTERNAL_INSTALL_PREFIX AND EXISTS "${EXTERNAL_INSTALL_PREFIX}/lib")
        list(APPEND _ep_dirs "${EXTERNAL_INSTALL_PREFIX}/lib")
    endif()
    set_property(GLOBAL PROPERTY _EP_BINARYDEPS_EP_DIRS "${_ep_dirs}")

    # ── TOOLCHAIN ────────────────────────────────────────────────────────────
    # Знаходимо директорію runtime-бібліотек компілятора (libgcc, libstdc++).
    set(_tc_dirs "")
    if(CMAKE_C_COMPILER)
        execute_process(
            COMMAND "${CMAKE_C_COMPILER}" -print-libgcc-file-name
            OUTPUT_VARIABLE _libgcc_path
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET)
        if(_libgcc_path AND NOT _libgcc_path MATCHES "NOTFOUND")
            get_filename_component(_libgcc_dir "${_libgcc_path}" DIRECTORY)
            if(EXISTS "${_libgcc_dir}")
                list(APPEND _tc_dirs "${_libgcc_dir}")
            endif()
            # GCC може мати бібліотеки на рівень вище (multilib)
            get_filename_component(_tc_parent "${_libgcc_dir}" DIRECTORY)
            if(EXISTS "${_tc_parent}" AND NOT "${_tc_parent}" STREQUAL "${_libgcc_dir}")
                list(APPEND _tc_dirs "${_tc_parent}")
            endif()
        endif()
    endif()
    set_property(GLOBAL PROPERTY _EP_BINARYDEPS_TC_DIRS "${_tc_dirs}")

    # ── SYSROOT ──────────────────────────────────────────────────────────────
    set(_sr_dirs "")
    if(CMAKE_SYSROOT)
        foreach(_base "${CMAKE_SYSROOT}/lib" "${CMAKE_SYSROOT}/usr/lib")
            if(EXISTS "${_base}")
                list(APPEND _sr_dirs "${_base}")
            endif()
            # multiarch-підкаталоги (aarch64-linux-gnu, arm-linux-gnueabihf тощо)
            file(GLOB _multiarch_dirs "${_base}/*-linux-*")
            list(APPEND _sr_dirs ${_multiarch_dirs})
        endforeach()
    endif()
    set_property(GLOBAL PROPERTY _EP_BINARYDEPS_SR_DIRS "${_sr_dirs}")

    # ── SYSTEM (хост) ────────────────────────────────────────────────────────
    set(_sys_dirs "")
    foreach(_base "/lib" "/usr/lib" "/lib64" "/usr/lib64")
        if(EXISTS "${_base}")
            list(APPEND _sys_dirs "${_base}")
        endif()
    endforeach()
    # multiarch хоста
    file(GLOB _host_multiarch "/usr/lib/*-linux-*")
    list(APPEND _sys_dirs ${_host_multiarch})
    set_property(GLOBAL PROPERTY _EP_BINARYDEPS_SYS_DIRS "${_sys_dirs}")

    set(_EP_BINARYDEPS_SEARCH_DIRS_BUILT TRUE CACHE INTERNAL "")
endfunction()

# ---------------------------------------------------------------------------
# Внутрішній хелпер: шукає soname у списку директорій
# Повертає повний шлях або порожній рядок
# ---------------------------------------------------------------------------
function(_ep_binarydeps_find_in_dirs out_path soname)
    foreach(_dir ${ARGN})
        if(EXISTS "${_dir}/${soname}")
            set(${out_path} "${_dir}/${soname}" PARENT_SCOPE)
            return()
        endif()
        # Версовані симлінки типу libfoo.so.1.2.3
        file(GLOB _candidates "${_dir}/${soname}*")
        if(_candidates)
            list(GET _candidates 0 _first)
            set(${out_path} "${_first}" PARENT_SCOPE)
            return()
        endif()
    endforeach()
    set(${out_path} "" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# Внутрішній рекурсивний обхід
# ---------------------------------------------------------------------------
function(_ep_binarydeps_recurse full_path depth)
    # Захист від циклів
    get_property(_visited GLOBAL PROPERTY _EP_BINARYDEPS_VISITED)
    if("${full_path}" IN_LIST _visited)
        return()
    endif()
    set_property(GLOBAL APPEND PROPERTY _EP_BINARYDEPS_VISITED "${full_path}")

    if(NOT EXISTS "${full_path}")
        return()
    endif()

    # Отримуємо NEEDED бібліотеки через readelf
    get_property(_readelf GLOBAL PROPERTY _EP_BINARYDEPS_READELF)
    execute_process(
        COMMAND "${_readelf}" -d "${full_path}"
        OUTPUT_VARIABLE _readelf_out
        ERROR_QUIET)

    # Відступ для виводу дерева
    string(REPEAT "  " ${depth} _indent)

    # Отримуємо списки директорій
    get_property(_ep_dirs  GLOBAL PROPERTY _EP_BINARYDEPS_EP_DIRS)
    get_property(_tc_dirs  GLOBAL PROPERTY _EP_BINARYDEPS_TC_DIRS)
    get_property(_sr_dirs  GLOBAL PROPERTY _EP_BINARYDEPS_SR_DIRS)
    get_property(_sys_dirs GLOBAL PROPERTY _EP_BINARYDEPS_SYS_DIRS)

    # Парсимо рядки виду:  0x0001 (NEEDED) Shared library: [libfoo.so.1]
    string(REPLACE "\n" ";" _lines "${_readelf_out}")
    foreach(_line ${_lines})
        if(NOT _line MATCHES "\\(NEEDED\\)")
            continue()
        endif()
        if(NOT _line MATCHES "\\[(.+)\\]")
            continue()
        endif()
        set(_soname "${CMAKE_MATCH_1}")

        # Класифікуємо
        _ep_binarydeps_find_in_dirs(_found_ep  "${_soname}" ${_ep_dirs})
        _ep_binarydeps_find_in_dirs(_found_tc  "${_soname}" ${_tc_dirs})
        _ep_binarydeps_find_in_dirs(_found_sr  "${_soname}" ${_sr_dirs})
        _ep_binarydeps_find_in_dirs(_found_sys "${_soname}" ${_sys_dirs})

        if(_found_ep)
            message(STATUS "${_indent}[EP]        ${_soname}  (${_found_ep})")
            set_property(GLOBAL APPEND PROPERTY _EP_BINARYDEPS_SUMMARY_EP "${_soname}")
            math(EXPR _next "${depth} + 1")
            _ep_binarydeps_recurse("${_found_ep}" ${_next})
        elseif(_found_tc)
            message(STATUS "${_indent}[TOOLCHAIN] ${_soname}  (${_found_tc})")
            set_property(GLOBAL APPEND PROPERTY _EP_BINARYDEPS_SUMMARY_TC "${_soname}")
            math(EXPR _next "${depth} + 1")
            _ep_binarydeps_recurse("${_found_tc}" ${_next})
        elseif(_found_sr)
            message(STATUS "${_indent}[SYSROOT]   ${_soname}")
            set_property(GLOBAL APPEND PROPERTY _EP_BINARYDEPS_SUMMARY_SR "${_soname}")
        elseif(_found_sys)
            message(STATUS "${_indent}[SYSTEM]    ${_soname}")
            set_property(GLOBAL APPEND PROPERTY _EP_BINARYDEPS_SUMMARY_SYS "${_soname}")
        else()
            message(STATUS "${_indent}[MISSING]   ${_soname}")
            set_property(GLOBAL APPEND PROPERTY _EP_BINARYDEPS_SUMMARY_MISSING "${_soname}")
        endif()
    endforeach()
endfunction()

# ---------------------------------------------------------------------------
# ep_check_binary_deps(<binary_path>)
#
# Публічна функція. Скидає стан, запускає рекурсивний обхід, виводить зведення.
# ---------------------------------------------------------------------------
function(ep_check_binary_deps binary_path)
    if(NOT EXISTS "${binary_path}")
        message(WARNING "[BinaryDeps] Файл не знайдено: ${binary_path}")
        return()
    endif()

    # Знаходимо readelf один раз
    if(CMAKE_READELF)
        set(_readelf "${CMAKE_READELF}")
    else()
        find_program(_readelf_prog readelf)
        if(NOT _readelf_prog)
            message(FATAL_ERROR "[BinaryDeps] readelf не знайдено в PATH")
        endif()
        set(_readelf "${_readelf_prog}")
    endif()
    set_property(GLOBAL PROPERTY _EP_BINARYDEPS_READELF "${_readelf}")

    # Скидаємо стан попереднього запуску
    set_property(GLOBAL PROPERTY _EP_BINARYDEPS_VISITED        "")
    set_property(GLOBAL PROPERTY _EP_BINARYDEPS_SUMMARY_EP      "")
    set_property(GLOBAL PROPERTY _EP_BINARYDEPS_SUMMARY_TC      "")
    set_property(GLOBAL PROPERTY _EP_BINARYDEPS_SUMMARY_SR      "")
    set_property(GLOBAL PROPERTY _EP_BINARYDEPS_SUMMARY_SYS     "")
    set_property(GLOBAL PROPERTY _EP_BINARYDEPS_SUMMARY_MISSING "")

    # Будуємо таблицю пошукових директорій
    _ep_binarydeps_build_search_dirs()

    message(STATUS "")
    message(STATUS "[BinaryDeps] ${binary_path}")
    message(STATUS "[BinaryDeps] ─────────────────────────────────────────")

    _ep_binarydeps_recurse("${binary_path}" 1)

    # ── Зведення ────────────────────────────────────────────────────────────
    get_property(_ep_libs      GLOBAL PROPERTY _EP_BINARYDEPS_SUMMARY_EP)
    get_property(_tc_libs      GLOBAL PROPERTY _EP_BINARYDEPS_SUMMARY_TC)
    get_property(_sr_libs      GLOBAL PROPERTY _EP_BINARYDEPS_SUMMARY_SR)
    get_property(_sys_libs     GLOBAL PROPERTY _EP_BINARYDEPS_SUMMARY_SYS)
    get_property(_missing_libs GLOBAL PROPERTY _EP_BINARYDEPS_SUMMARY_MISSING)

    list(REMOVE_DUPLICATES _ep_libs)
    list(REMOVE_DUPLICATES _tc_libs)
    list(REMOVE_DUPLICATES _sr_libs)
    list(REMOVE_DUPLICATES _sys_libs)

    list(LENGTH _ep_libs      _n_ep)
    list(LENGTH _tc_libs      _n_tc)
    list(LENGTH _sr_libs      _n_sr)
    list(LENGTH _sys_libs     _n_sys)
    list(LENGTH _missing_libs _n_missing)

    message(STATUS "[BinaryDeps] ─────────────────────────────────────────")
    message(STATUS "[BinaryDeps] Зведення:")
    message(STATUS "[BinaryDeps]   [EP]        ${_n_ep} бібліотек(и)")
    message(STATUS "[BinaryDeps]   [TOOLCHAIN] ${_n_tc} бібліотек(и)")
    message(STATUS "[BinaryDeps]   [SYSROOT]   ${_n_sr} бібліотек(и)")
    message(STATUS "[BinaryDeps]   [SYSTEM]    ${_n_sys} бібліотек(и)")
    if(_missing_libs)
        list(REMOVE_DUPLICATES _missing_libs)
        string(JOIN ", " _missing_str ${_missing_libs})
        message(WARNING "[BinaryDeps]   [MISSING]   ${_n_missing}: ${_missing_str}")
    endif()
    message(STATUS "")
endfunction()
