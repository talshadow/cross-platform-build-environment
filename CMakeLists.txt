cmake_minimum_required(VERSION 3.20)

project(SupportRaspberryPI
    VERSION     1.0.0
    DESCRIPTION "Cross-platform CMake build support for Raspberry Pi and Yocto Linux"
    LANGUAGES   C CXX
)

# ---------------------------------------------------------------------------
# Superbuild режим
# Якщо SUPERBUILD=ON — збирає всі сторонні залежності як ExternalProject,
# потім основний проєкт. return() зупиняє обробку файлу далі.
# ---------------------------------------------------------------------------
option(SUPERBUILD
    "Збирати залежності та основний проєкт через Superbuild (ExternalProject)"
    OFF)

if(SUPERBUILD)
    include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/SuperBuild.cmake")
    return()
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildConfig.cmake")

# ---------------------------------------------------------------------------
# Цілі проєкту
# Додайте тут ваші цілі (add_library / add_executable).
# Приклад:
#
# add_executable(my_app main.cpp)
# target_include_directories(my_app PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
# target_enable_warnings(my_app STRICT)
# if(ENABLE_ASAN)
#     target_enable_sanitizers(my_app ASAN UBSAN)
# endif()
# ---------------------------------------------------------------------------
