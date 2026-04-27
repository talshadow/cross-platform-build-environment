# cmake/modules/Generate.cmake
#
# generate(<input.in> [OUTPUT_VAR <var>])
#
# Конфігурує файл .in через configure_file(@ONLY) і записує результат у
#   ${CMAKE_BINARY_DIR}/local_generated/<filename_without_.in>
#
# Параметри:
#   <input.in>        — шлях до .in файлу; відносний — від CMAKE_CURRENT_SOURCE_DIR
#   OUTPUT_VAR <var>  — (необов'язково) змінна, в яку записується повний шлях
#                       до згенерованого файлу (зручно для додавання до target_sources)
#
# Приклад:
#   generate("config/version.h.in" OUTPUT_VAR _version_h)
#   target_sources(my_app PRIVATE "${_version_h}")
#   target_include_directories(my_app PRIVATE "${CMAKE_BINARY_DIR}/local_generated")

function(generate INPUT_FILE)
    cmake_parse_arguments(_GEN "" "OUTPUT_VAR" "" ${ARGN})

    # Резолвимо відносний шлях від CMAKE_CURRENT_SOURCE_DIR
    if(NOT IS_ABSOLUTE "${INPUT_FILE}")
        set(INPUT_FILE "${CMAKE_CURRENT_SOURCE_DIR}/${INPUT_FILE}")
    endif()

    if(NOT EXISTS "${INPUT_FILE}")
        message(FATAL_ERROR "[Generate] Файл не знайдено: ${INPUT_FILE}")
    endif()

    # Видаляємо .in з імені файлу
    get_filename_component(_gen_name "${INPUT_FILE}" NAME)
    if(_gen_name MATCHES "\\.in$")
        string(REGEX REPLACE "\\.in$" "" _gen_out_name "${_gen_name}")
    else()
        message(WARNING "[Generate] Файл '${_gen_name}' не має розширення .in — "
            "вихідне ім'я залишається незмінним")
        set(_gen_out_name "${_gen_name}")
    endif()

    set(_gen_out_dir  "${CMAKE_BINARY_DIR}/local_generated")
    set(_gen_out_file "${_gen_out_dir}/${_gen_out_name}")

    configure_file("${INPUT_FILE}" "${_gen_out_file}" @ONLY)

    message(STATUS "[Generate] ${INPUT_FILE} → ${_gen_out_file}")

    if(DEFINED _GEN_OUTPUT_VAR)
        set(${_GEN_OUTPUT_VAR} "${_gen_out_file}" PARENT_SCOPE)
    endif()
endfunction()
