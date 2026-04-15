# cmake/BuildConfig.cmake
#
# Конфігурація збірки проєкту. Підключається з кореневого CMakeLists.txt
# після project() і перевірки SUPERBUILD.
#
# Налаштовує: стандарти C/C++, директорії виводу, модулі, опції збірки,
# LTO, діагностику крос-компіляції, сторонні залежності, тести.

# ---------------------------------------------------------------------------
# Стандарт C++
# ---------------------------------------------------------------------------
set(CMAKE_CXX_STANDARD          23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS        OFF)

set(CMAKE_C_STANDARD          11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS        OFF)

# ---------------------------------------------------------------------------
# Директорія виводу
# ---------------------------------------------------------------------------
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

# ---------------------------------------------------------------------------
# Модулі
# ---------------------------------------------------------------------------
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/modules")

include(CompilerWarnings)
include(Sanitizers)
include(CrossCompileHelpers)
include(GitVersion)

git_get_version(PROJECT_GIT_VERSION FALLBACK "0.0.0")
git_get_commit_hash(PROJECT_GIT_HASH)
message(STATUS "Версія: ${PROJECT_GIT_VERSION}  коміт: ${PROJECT_GIT_HASH}")

# ---------------------------------------------------------------------------
# Опції збірки
# ---------------------------------------------------------------------------
option(BUILD_TESTS    "Збирати тести"                ON)
option(ENABLE_ASAN    "Увімкнути AddressSanitizer"   OFF)
option(ENABLE_UBSAN   "Увімкнути UBSanitizer"        OFF)
option(ENABLE_TSAN    "Увімкнути ThreadSanitizer"    OFF)
option(ENABLE_LTO     "Увімкнути Link-Time Optimization" OFF)

# ---------------------------------------------------------------------------
# LTO
# ---------------------------------------------------------------------------
if(ENABLE_LTO)
    include(CheckIPOSupported)
    check_ipo_supported(RESULT _IPO_OK OUTPUT _IPO_ERR)
    if(_IPO_OK)
        set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)
        message(STATUS "LTO увімкнено")
    else()
        message(WARNING "LTO не підтримується: ${_IPO_ERR}")
    endif()
endif()

# ---------------------------------------------------------------------------
# Діагностика крос-компіляції
# ---------------------------------------------------------------------------
cross_get_target_info()

# ---------------------------------------------------------------------------
# Сторонні залежності (ExternalProject або системні)
# ---------------------------------------------------------------------------
include("${CMAKE_SOURCE_DIR}/cmake/external/ExternalDeps.cmake")

# ---------------------------------------------------------------------------
# Тести
# ---------------------------------------------------------------------------
if(BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
