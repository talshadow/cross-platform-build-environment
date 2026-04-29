# cmake/external/Eigen3.cmake
#
# Eigen3 — C++ бібліотека лінійної алгебри (матриці, вектори, чисельні методи).
# Бібліотека повністю header-only: немає .so, лише заголовкові файли.
# https://eigen.tuxfamily.org/
#
# Provides imported target:
#   Eigen3::Eigen  — INTERFACE IMPORTED (header-only)
#
# Опції:
#   USE_SYSTEM_EIGEN3   — ON: find_package в системі/sysroot
#                         OFF (за замовч.): зібрати через ExternalProject
#   EIGEN_USE_BLAS      — ON (за замовч.): додати EIGEN_USE_BLAS до INTERFACE_COMPILE_DEFINITIONS
#                         таргету Eigen3::Eigen. Потребує libblas-dev або libopenblas-dev в sysroot.
#   EIGEN_USE_LAPACKE   — ON (за замовч.): додати EIGEN_USE_LAPACKE до INTERFACE_COMPILE_DEFINITIONS
#                         таргету Eigen3::Eigen. Потребує liblapacke-dev в sysroot.
#
# Кеш-змінні:
#   EIGEN3_VERSION    — версія (git тег)
#   EIGEN3_GIT_REPO   — URL git репозиторію

option(USE_SYSTEM_EIGEN3
    "Використовувати системний Eigen3 замість встановлення з джерел"
    OFF)

option(EIGEN_USE_BLAS
    "Увімкнути BLAS-бекенд для Eigen (EIGEN_USE_BLAS; потребує libblas-dev або libopenblas-dev в sysroot)"
    ON)

option(EIGEN_USE_LAPACKE
    "Увімкнути LAPACKE-бекенд для Eigen (EIGEN_USE_LAPACKE; потребує liblapacke-dev в sysroot)"
    ON)

set(EIGEN3_VERSION "3.4.0"
    CACHE STRING "Версія Eigen3 для встановлення з джерел")

set(EIGEN3_GIT_REPO
    "https://gitlab.com/libeigen/eigen.git"
    CACHE STRING "Git репозиторій Eigen3 (GitLab — офіційний upstream)")

# ---------------------------------------------------------------------------
# Eigen встановлює заголовки у <prefix>/include/eigen3/
# Представницький файл як маркер для Ninja (BUILD_BYPRODUCTS)
set(_eigen_inc "${EXTERNAL_INSTALL_PREFIX}/include/eigen3")
set(_eigen_hdr "${_eigen_inc}/Eigen/Core")

if(USE_SYSTEM_EIGEN3)
    # ── Системна бібліотека / sysroot ───────────────────────────────────────
    find_package(Eigen3 REQUIRED)
    message(STATUS "[Eigen3] Системна: ${EIGEN3_VERSION_STRING} (include: ${EIGEN3_INCLUDE_DIRS})")

else()
    # ── Алгоритм: find_package → ExternalProject_Add ────────────────────────
    # Eigen встановлює Eigen3Config.cmake → find_package знайде його
    # в EXTERNAL_INSTALL_PREFIX через HINTS.
    find_package(Eigen3 QUIET
        HINTS "${EXTERNAL_INSTALL_PREFIX}"
        NO_DEFAULT_PATH)

    if(Eigen3_FOUND)
        message(STATUS "[Eigen3] Знайдено готову бібліотеку у ${EXTERNAL_INSTALL_PREFIX}")
        # Eigen3::Eigen вже створено find_package

    elseif(EXISTS "${_eigen_hdr}")
        ep_imported_interface(Eigen3::Eigen "${_eigen_inc}")
        message(STATUS "[Eigen3] Знайдено заголовки у ${EXTERNAL_INSTALL_PREFIX}")

    else()
        message(STATUS "[Eigen3] Буде встановлено з джерел (${EIGEN3_VERSION})")

        # Eigen — header-only: CMake install копіює заголовки, нічого не компілює.
        # ep_cmake_args передає toolchain/sysroot (не потрібні для header-only,
        # але залишаємо для уніфікації). BUILD_SHARED_LIBS=ON з ep_cmake_args
        # Eigen ігнорує — це теж нешкідливо.
        ep_cmake_args(_eigen_cmake_args
            -DEIGEN_BUILD_DOC=OFF
            -DBUILD_TESTING=OFF
        )

        # Eigen не має залежностей від наших бібліотек
        ExternalProject_Add(eigen3_ep
            GIT_REPOSITORY  "${EIGEN3_GIT_REPO}"
            GIT_TAG         "${EIGEN3_VERSION}"
            GIT_SHALLOW     ON
            SOURCE_DIR      "${EP_SOURCES_DIR}/eigen3"
            CMAKE_ARGS      ${_eigen_cmake_args}
            # Заголовковий файл як маркер встановлення для Ninja
            BUILD_BYPRODUCTS "${_eigen_hdr}"
            LOG_DOWNLOAD    ON
            LOG_BUILD       ON
            LOG_INSTALL     ON
        )

        ep_imported_interface_from_ep(Eigen3::Eigen eigen3_ep "${_eigen_inc}")
        ep_track_cmake_file(eigen3_ep "${CMAKE_CURRENT_LIST_FILE}")
    endif()
endif()

# EIGEN_USE_BLAS / EIGEN_USE_LAPACKE — препроцесорні дефайни для коду користувача,
# не CMake-опції самого Eigen. Прокидаємо через INTERFACE_COMPILE_DEFINITIONS лише якщо
# відповідні бібліотеки і заголовки реально присутні в sysroot або нашому prefix.
# Перевіряємо .so (не .so.N) як маркер dev-пакету: versioned .so.N є без dev-пакету
# і недостатній для лінкування.
if(TARGET Eigen3::Eigen AND (EIGEN_USE_BLAS OR EIGEN_USE_LAPACKE))
    # Формуємо впорядковані списки директорій для пошуку: спочатку наш prefix,
    # потім sysroot (або системний /usr/lib при нативній збірці).
    set(_eigen_lib_dirs "${EXTERNAL_INSTALL_PREFIX}/lib")
    set(_eigen_inc_dirs "${EXTERNAL_INSTALL_PREFIX}/include")
    if(CMAKE_SYSROOT)
        set(_sr_lib "${CMAKE_SYSROOT}/usr/lib")
        if(CMAKE_LIBRARY_ARCHITECTURE)
            list(APPEND _eigen_lib_dirs
                "${_sr_lib}/${CMAKE_LIBRARY_ARCHITECTURE}/blas"
                "${_sr_lib}/${CMAKE_LIBRARY_ARCHITECTURE}/lapack"
                "${_sr_lib}/${CMAKE_LIBRARY_ARCHITECTURE}")
        endif()
        list(APPEND _eigen_lib_dirs "${_sr_lib}")
        list(APPEND _eigen_inc_dirs "${CMAKE_SYSROOT}/usr/include")
        unset(_sr_lib)
    else()
        if(CMAKE_LIBRARY_ARCHITECTURE)
            list(APPEND _eigen_lib_dirs
                "/usr/lib/${CMAKE_LIBRARY_ARCHITECTURE}/blas"
                "/usr/lib/${CMAKE_LIBRARY_ARCHITECTURE}/lapack"
                "/usr/lib/${CMAKE_LIBRARY_ARCHITECTURE}")
        endif()
        list(APPEND _eigen_lib_dirs "/usr/lib")
        list(APPEND _eigen_inc_dirs "/usr/include")
    endif()

    # Хелпер: шукає перший збіг з іменами файлів у заданих директоріях
    macro(_eigen_find_first _result _dirs)
        set(${_result} "")
        foreach(_d ${${_dirs}})
            foreach(_name ${ARGN})
                if(EXISTS "${_d}/${_name}")
                    set(${_result} "${_d}/${_name}")
                    break()
                endif()
            endforeach()
            if(${_result})
                break()
            endif()
        endforeach()
    endmacro()

    if(EIGEN_USE_BLAS)
        _eigen_find_first(_blas_lib _eigen_lib_dirs "libblas.so" "libopenblas.so")
        _eigen_find_first(_blas_hdr _eigen_inc_dirs "cblas.h")
        if(_blas_lib AND _blas_hdr)
            set_property(TARGET Eigen3::Eigen APPEND PROPERTY
                INTERFACE_COMPILE_DEFINITIONS EIGEN_USE_BLAS)
            message(STATUS "[Eigen3] EIGEN_USE_BLAS: увімкнено (${_blas_lib})")
        elseif(NOT _blas_lib)
            message(STATUS "[Eigen3] EIGEN_USE_BLAS: libblas.so/libopenblas.so не знайдено — вимкнено")
        else()
            message(STATUS "[Eigen3] EIGEN_USE_BLAS: cblas.h не знайдено — вимкнено")
        endif()
        unset(_blas_lib)
        unset(_blas_hdr)
    endif()

    if(EIGEN_USE_LAPACKE)
        _eigen_find_first(_lapacke_lib _eigen_lib_dirs "liblapacke.so")
        _eigen_find_first(_lapacke_hdr _eigen_inc_dirs "lapacke.h")
        if(_lapacke_lib AND _lapacke_hdr)
            set_property(TARGET Eigen3::Eigen APPEND PROPERTY
                INTERFACE_COMPILE_DEFINITIONS EIGEN_USE_LAPACKE)
            message(STATUS "[Eigen3] EIGEN_USE_LAPACKE: увімкнено (${_lapacke_lib})")
        elseif(NOT _lapacke_lib)
            message(STATUS "[Eigen3] EIGEN_USE_LAPACKE: liblapacke.so не знайдено — вимкнено")
        else()
            message(STATUS "[Eigen3] EIGEN_USE_LAPACKE: lapacke.h не знайдено — вимкнено")
        endif()
        unset(_lapacke_lib)
        unset(_lapacke_hdr)
    endif()

    unset(_eigen_lib_dirs)
    unset(_eigen_inc_dirs)
endif()

unset(_eigen_inc)
unset(_eigen_hdr)
