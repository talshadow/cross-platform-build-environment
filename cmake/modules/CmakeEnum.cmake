# cmake/modules/CmakeEnum.cmake
#
# Оголошення та валідація CMake cache-змінних з фіксованим набором значень.
# Забезпечує випадаючий список у GUI (cmake-gui / ccmake) і перевірку значення.
#
# Використання:
#   include(CmakeEnum)
#
#   declare_cmake_enum(MY_MODE "Release" "Режим збірки" Debug Release MinSizeRel)
#   validate_cmake_enum(MY_MODE)
#
# declare_cmake_enum(<VAR> <DEFAULT> <DOC> <value1> [value2 ...])
#   VAR     — ім'я кеш-змінної
#   DEFAULT — значення за замовчуванням (має бути з дозволеного списку)
#   DOC     — рядок документації для cmake-gui
#   values  — дозволені значення (один або більше)
#
# validate_cmake_enum(<VAR>)
#   Викидає FATAL_ERROR якщо поточне значення VAR не є в дозволеному списку.
#   Виводить STATUS якщо значення коректне.

cmake_policy(SET CMP0057 NEW)  # підтримка IN_LIST (CMake 3.3+; NEW за замовч. з 3.28)

# ---------------------------------------------------------------------------
function(declare_cmake_enum VAR_NAME DEFAULT DOC)
    set(_allowed ${ARGN})

    if(NOT _allowed)
        message(FATAL_ERROR "[declare_cmake_enum] Список допустимих значень не може бути порожнім (${VAR_NAME})")
    endif()

    if(NOT "${DEFAULT}" IN_LIST _allowed)
        string(REPLACE ";" ", " _print "${_allowed}")
        message(FATAL_ERROR
            "[declare_cmake_enum] DEFAULT='${DEFAULT}' для ${VAR_NAME} не входить до списку дозволених: [${_print}]")
    endif()

    set(${VAR_NAME} "${DEFAULT}" CACHE STRING "${DOC}")

    # STRINGS — для випадаючого списку в cmake-gui / ccmake та для валідації
    set_property(CACHE ${VAR_NAME} PROPERTY STRINGS ${_allowed})
endfunction()

# ---------------------------------------------------------------------------
function(validate_cmake_enum VAR_NAME)
    get_property(_allowed CACHE ${VAR_NAME} PROPERTY STRINGS)

    if(NOT _allowed)
        message(FATAL_ERROR "[validate_cmake_enum] Змінна '${VAR_NAME}' не має STRINGS property — оголосіть через declare_cmake_enum")
    endif()

    if(NOT ${VAR_NAME} IN_LIST _allowed)
        string(REPLACE ";" ", " _print "${_allowed}")
        message(FATAL_ERROR
            "[validate_cmake_enum] '${${VAR_NAME}}' — недопустиме значення для ${VAR_NAME}. "
            "Оберіть одне з: [${_print}]")
    endif()

    message(STATUS "[CmakeEnum] ${VAR_NAME} = ${${VAR_NAME}}")
endfunction()
