# cmake/modules/GitVersion.cmake
#
# Функції для отримання версії та хешу коміту з git.
#
# Використання:
#   include(GitVersion)
#   git_get_version(MY_VERSION)          # → "1.2.3.4" або "0.0.0.0" якщо тег відсутній
#   git_get_commit_hash(MY_HASH)         # → "a1b2c3d" або "unknown"
#
# git_get_version(<OUT_VAR> [FALLBACK <version>])
#   OUT_VAR  — змінна, куди записується версія у форматі W.X.Y.Z
#   FALLBACK — версія за замовчуванням, якщо git недоступний або тег не знайдено
#              (за замовчуванням "0.0.0")
#
# git_get_commit_hash(<OUT_VAR> [LENGTH <n>])
#   OUT_VAR — змінна, куди записується скорочений хеш останнього коміту
#   LENGTH  — кількість символів хешу (за замовчуванням 7)

# ---------------------------------------------------------------------------
function(git_get_version OUT_VAR)
    cmake_parse_arguments(_GV "" "FALLBACK" "" ${ARGN})

    if(NOT DEFINED _GV_FALLBACK)
        set(_GV_FALLBACK "0.0.0.0")
    endif()

    find_package(Git QUIET)

    if(NOT GIT_FOUND)
        message(WARNING "GitVersion: git не знайдено, використовується FALLBACK=${_GV_FALLBACK}")
        set(${OUT_VAR} "${_GV_FALLBACK}" PARENT_SCOPE)
        return()
    endif()

    # Шукаємо найближчий тег у форматі X.Y.Z або vX.Y.Z
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" describe --tags --match "[0-9]*.[0-9]*.[0-9]*.[0-9]*" --abbrev=0
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        OUTPUT_VARIABLE _GV_RAW
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _GV_RESULT
    )

    # Якщо перший пошук не знайшов — спробуємо з префіксом "v"
    if(NOT _GV_RESULT EQUAL 0 OR _GV_RAW STREQUAL "")
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" describe --tags --match "v[0-9]*.[0-9]*.[0-9]*.[0-9]*" --abbrev=0
            WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
            OUTPUT_VARIABLE _GV_RAW
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
            RESULT_VARIABLE _GV_RESULT
        )
    endif()

    if(NOT _GV_RESULT EQUAL 0 OR _GV_RAW STREQUAL "")
        message(WARNING "GitVersion: тег не знайдено, використовується FALLBACK=${_GV_FALLBACK}")
        set(${OUT_VAR} "${_GV_FALLBACK}" PARENT_SCOPE)
        return()
    endif()

    # Видаляємо префікс "v" якщо є, залишаємо лише W.X.Y.Z
    string(REGEX REPLACE "^[vV]" "" _GV_VERSION "${_GV_RAW}")

    # Перевіряємо формат W.X.Y.Z
    if(NOT _GV_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")
        message(WARNING "GitVersion: тег '${_GV_RAW}' не відповідає формату W.X.Y.Z, "
                        "використовується FALLBACK=${_GV_FALLBACK}")
        set(${OUT_VAR} "${_GV_FALLBACK}" PARENT_SCOPE)
        return()
    endif()

    set(${OUT_VAR} "${_GV_VERSION}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
function(git_get_commit_hash OUT_VAR)
    cmake_parse_arguments(_GH "" "LENGTH" "" ${ARGN})

    if(NOT DEFINED _GH_LENGTH)
        set(_GH_LENGTH 7)
    endif()

    find_package(Git QUIET)

    if(NOT GIT_FOUND)
        message(WARNING "GitVersion: git не знайдено, хеш = 'unknown'")
        set(${OUT_VAR} "unknown" PARENT_SCOPE)
        return()
    endif()

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" rev-parse "--short=${_GH_LENGTH}" HEAD
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        OUTPUT_VARIABLE _GH_HASH
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _GH_RESULT
    )

    if(NOT _GH_RESULT EQUAL 0 OR _GH_HASH STREQUAL "")
        message(WARNING "GitVersion: не вдалося отримати хеш коміту, хеш = 'unknown'")
        set(${OUT_VAR} "unknown" PARENT_SCOPE)
        return()
    endif()

    set(${OUT_VAR} "${_GH_HASH}" PARENT_SCOPE)
endfunction()
