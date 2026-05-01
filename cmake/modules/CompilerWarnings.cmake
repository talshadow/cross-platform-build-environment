# cmake/modules/CompilerWarnings.cmake
#
# Функція target_enable_warnings() — додає стандартний набір
# попереджень компілятора до цільового таргету.
#
# Використання:
#   include(CompilerWarnings)
#   target_enable_warnings(my_target)           # рівень NORMAL
#   target_enable_warnings(my_target STRICT)    # рівень STRICT (більше попереджень)
#   target_enable_warnings(my_target PEDANTIC)  # STRICT + -Wpedantic

# ---------------------------------------------------------------------------
function(target_enable_warnings TARGET)
    set(_LEVEL "NORMAL")
    if(ARGC GREATER 1)
        set(_LEVEL "${ARGV1}")
    endif()

    # Попередження, спільні для GCC та Clang
    set(_COMMON_WARNINGS
        -Wall
        -Wextra
        -Wshadow
        -Wnon-virtual-dtor
        -Wcast-align
        -Wunused
        -Woverloaded-virtual
        -Wconversion
        -Wsign-conversion
        -Wdouble-promotion
        -Wformat=2
        -Wimplicit-fallthrough
        -Wnull-dereference
    )

    if(_LEVEL STREQUAL "STRICT" OR _LEVEL STREQUAL "PEDANTIC")
        list(APPEND _COMMON_WARNINGS
            -Wmisleading-indentation
            -Wduplicated-cond
            -Wduplicated-branches
            -Wlogical-op
            -Wuseless-cast
        )
    endif()

    if(_LEVEL STREQUAL "PEDANTIC")
        list(APPEND _COMMON_WARNINGS -Wpedantic)
    endif()

    # Clang-специфічні попередження
    set(_CLANG_EXTRA
        -Wno-gnu-zero-variadic-macro-arguments
    )

    # MSVC
    set(_MSVC_WARNINGS
        /W4
        /w14242  # 'identifier': conversion from 'type1' to 'type2'
        /w14254  # 'operator': conversion from 'type1:field_bits' to 'type2:field_bits'
        /w14263  # 'function': member function does not override any base class virtual member function
        /w14265  # 'classname': class has virtual functions, but destructor is not virtual
        /w14287  # 'operator': unsigned/negative constant mismatch
        /we4289  # nonstandard extension used: 'variable': loop control variable declared in the for-loop
        /w14296  # 'operator': expression is always 'boolean_value'
        /w14311  # 'variable': pointer truncation from 'type1' to 'type2'
        /w14545  # expression before comma evaluates to a function which is missing an argument list
        /w14546  # function call before comma missing argument list
        /w14547  # 'operator': operator before comma has no effect
        /w14549  # 'operator': operator before comma has no effect; did you intend 'operator'?
        /w14555  # expression has no effect; expected expression with side-effect
        /w14619  # pragma warning: there is no warning number 'number'
        /w14640  # Enable warning on thread un-safe static member initialization
        /w14826  # Conversion from 'type1' to 'type_2' is sign-extended
        /w14905  # wide string literal cast to 'LPSTR'
        /w14906  # string literal cast to 'LPWSTR'
        /w14928  # illegal copy-initialization; more than one user-defined conversion has been implicitly applied
    )

    if(MSVC)
        target_compile_options("${TARGET}" PRIVATE ${_MSVC_WARNINGS})
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        target_compile_options("${TARGET}" PRIVATE
            ${_COMMON_WARNINGS}
            ${_CLANG_EXTRA})
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        target_compile_options("${TARGET}" PRIVATE ${_COMMON_WARNINGS})
    else()
        message(WARNING
            "[target_enable_warnings] невідомий компілятор '${CMAKE_CXX_COMPILER_ID}' "
            "для таргету '${TARGET}' — попередження не застосовано")
    endif()
endfunction()
