# cmake/modules/StripDebug.cmake
#
# Додає цілі для стрипування debug інформації з артефактів збірки.
#
# Використання:
#   include(StripDebug)
#   target_add_strip_targets(my_app)
#
# Функції:
#   target_add_strip_targets(<target> [TARGETS target1 target2...])
#
# Створені цілі:
#   strip_debug   — видаляє тільки debug секції (.debug_*), виконавчий файл лишається
#                   придатним для profiling та backtrace (зберігає символи).
#   strip_all     — видаляє всі символи (мінімальний розмір)
#   strip_split   — копіює артефакти у <binaryDir>-stripped/, виносить debug info
#                   у .debug файли (підходить для remote debugging через gdb)
#
# Вихідна директорія стрипованих артефактів: <binaryDir>-stripped/
#
# Передумови:
#   CMAKE_STRIP повинен бути встановлений (автоматично для cross-toolchain).
#   Для strip_split також потрібен objcopy.

cmake_minimum_required(VERSION 3.28)

# ---------------------------------------------------------------------------
# _strip_define_target(<name> <commands_var> <deps> <comment>)
#
# Внутрішня утиліта. Створює custom target якщо він ще не існує.
#   commands_var — ім'я змінної (зі scope виклику) що містить список COMMAND ...
#   deps         — список цілей для DEPENDS
# ---------------------------------------------------------------------------
function(_strip_define_target name commands_var deps comment)
    if(NOT TARGET ${name})
        add_custom_target(${name}
            ${${commands_var}}
            DEPENDS ${deps}
            COMMENT "${comment}"
        )
    endif()
endfunction()

# ---------------------------------------------------------------------------
# _strip_find_objcopy
# Шукає objcopy: спочатку з тим самим префіксом що й CMAKE_STRIP,
# потім просто "objcopy".
# ---------------------------------------------------------------------------
function(_strip_find_objcopy out_var)
    if(CMAKE_STRIP)
        # Витягуємо префікс: arm-linux-gnueabihf-strip → arm-linux-gnueabihf-
        get_filename_component(_strip_name "${CMAKE_STRIP}" NAME)
        string(REGEX REPLACE "strip$" "objcopy" _objcopy_name "${_strip_name}")
        get_filename_component(_strip_dir  "${CMAKE_STRIP}" DIRECTORY)

        find_program(_objcopy_candidate
            NAMES "${_objcopy_name}"
            HINTS "${_strip_dir}"
            NO_DEFAULT_PATH)

        if(_objcopy_candidate)
            set(${out_var} "${_objcopy_candidate}" PARENT_SCOPE)
            return()
        endif()
    endif()

    find_program(_objcopy_fallback NAMES objcopy)
    set(${out_var} "${_objcopy_fallback}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# target_add_strip_targets(<main_target> [TARGETS t1 t2 ...])
#
# Додає три strip-цілі для заданих targets.
# Якщо TARGETS не вказано — стрипується сам <main_target>.
#
# Параметри:
#   <main_target>      — ім'я CMake target (обов'язково); використовується
#                        для виведення повідомлення та як fallback список
#   TARGETS t1 t2 ...  — додаткові targets для стрипування
# ---------------------------------------------------------------------------
function(target_add_strip_targets main_target)
    cmake_parse_arguments(_STRIP "" "" "TARGETS" ${ARGN})

    if(NOT TARGET ${main_target})
        message(WARNING "[StripDebug] Target '${main_target}' не існує, strip-цілі не створено")
        return()
    endif()

    if(NOT CMAKE_STRIP)
        message(WARNING "[StripDebug] CMAKE_STRIP не знайдено, strip-цілі не створено")
        return()
    endif()

    # Список targets для стрипування
    if(_STRIP_TARGETS)
        set(_targets ${_STRIP_TARGETS})
    else()
        set(_targets ${main_target})
    endif()

    # Вихідна директорія стрипованих файлів
    set(_stripped_dir "${CMAKE_BINARY_DIR}-stripped")

    # Збираємо команди для всіх targets
    set(_cmds_strip_debug "")
    set(_cmds_strip_all   "")
    set(_cmds_strip_split "")

    # Для split потрібен objcopy
    _strip_find_objcopy(_objcopy)

    foreach(_t IN LISTS _targets)
        if(NOT TARGET ${_t})
            message(WARNING "[StripDebug] Target '${_t}' не існує, пропущено")
            continue()
        endif()

        # Шлях до вихідного файлу target
        set(_src "$<TARGET_FILE:${_t}>")
        get_target_property(_t_type ${_t} TYPE)

        # --- strip_debug: видалити debug секції, зберегти символи ---
        list(APPEND _cmds_strip_debug
            COMMAND ${CMAKE_STRIP} --strip-debug "${_src}")

        # --- strip_all: видалити всі символи ---
        list(APPEND _cmds_strip_all
            COMMAND ${CMAKE_STRIP} --strip-all "${_src}")

        # --- strip_split: копіювати + split debug info ---
        set(_dst "${_stripped_dir}/$<TARGET_FILE_NAME:${_t}>")
        if(_objcopy)
            list(APPEND _cmds_strip_split
                COMMAND ${CMAKE_COMMAND} -E make_directory "${_stripped_dir}"
                COMMAND ${CMAKE_COMMAND} -E copy "${_src}" "${_dst}"
                COMMAND ${_objcopy} --only-keep-debug "${_src}" "${_dst}.debug"
                COMMAND ${_objcopy} --strip-debug --add-gnu-debuglink="${_dst}.debug" "${_dst}"
            )
        else()
            message(STATUS "[StripDebug] objcopy не знайдено, strip_split буде лише strip без .debug файлу")
            list(APPEND _cmds_strip_split
                COMMAND ${CMAKE_COMMAND} -E make_directory "${_stripped_dir}"
                COMMAND ${CMAKE_COMMAND} -E copy "${_src}" "${_dst}"
                COMMAND ${CMAKE_STRIP} --strip-all "${_dst}"
            )
        endif()
    endforeach()

    _strip_define_target(strip_debug _cmds_strip_debug "${_targets}"
        "Видалення debug секцій (--strip-debug)")
    _strip_define_target(strip_all _cmds_strip_all "${_targets}"
        "Видалення всіх символів (--strip-all)")
    _strip_define_target(strip_split _cmds_strip_split "${_targets}"
        "Копіювання у ${_stripped_dir}/ з окремим .debug файлом")

    message(STATUS "[StripDebug] Strip-цілі додано: strip_debug, strip_all, strip_split → ${_stripped_dir}/")
endfunction()
