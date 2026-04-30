# cmake/modules/RuntimeDeps.cmake
#
# Runtime-ресурси бібліотек з динамічними плагінами (IPA модулі, конфіги тощо).
# Підключається автоматично через Common.cmake.
#
# Надає:
#   ep_register_runtime_dirs(<target>
#       BASE_DIR <abs_path>
#       DIRS <rel_dir1> [<rel_dir2>...]
#       [NO_STRIP]
#       [SIGN_KEY <key_path>]
#   )
#     Реєструє runtime-директорії на IMPORTED target.
#     Викликати у Lib*.cmake після ep_imported_library_from_ep().
#
#     BASE_DIR  — абсолютний базовий шлях (зазвичай EXTERNAL_INSTALL_PREFIX)
#     DIRS      — відносні шляхи директорій відносно BASE_DIR
#                 Перший компонент шляху визначає destination при install:
#                   lib/libcamera  → INSTALL_PREFIX/lib/libcamera/
#                   share/libcamera → INSTALL_PREFIX/share/libcamera/
#     NO_STRIP  — не стріпати .so у цих директоріях (IPA-модулі мають підписи)
#     SIGN_KEY  — шлях до приватного ключа для strip + ре-підпису (опціонально)
#                 Якщо заданий і DO_STRIP=ON — .so стріпуються та ре-підписуються.
#                 Якщо не заданий і NO_STRIP — .so взагалі не стріпуються.
#
#   ep_collect_runtime_resources(<main_target> <out_file_var>)
#     Рекурсивно обходить LINK_LIBRARIES <main_target>, збирає всі
#     зареєстровані runtime-ресурси і записує cmake-файл у <out_file_var>.
#     Викликається автоматично з project_setup_install().

# ---------------------------------------------------------------------------
# ep_register_runtime_dirs
# ---------------------------------------------------------------------------
function(ep_register_runtime_dirs target)
    cmake_parse_arguments(_R "NO_STRIP" "BASE_DIR;SIGN_KEY" "DIRS" ${ARGN})

    if(NOT TARGET "${target}")
        message(FATAL_ERROR "[RuntimeDeps] ep_register_runtime_dirs: target '${target}' не існує")
    endif()
    if(NOT _R_BASE_DIR)
        message(FATAL_ERROR "[RuntimeDeps] ep_register_runtime_dirs: BASE_DIR обов'язковий")
    endif()
    if(NOT _R_DIRS)
        message(FATAL_ERROR "[RuntimeDeps] ep_register_runtime_dirs: DIRS обов'язковий")
    endif()

    set(_srcs "")
    set(_dsts "")
    foreach(_rel IN LISTS _R_DIRS)
        list(APPEND _srcs "${_R_BASE_DIR}/${_rel}")
        # Destination parent = перший компонент відносного шляху
        # lib/libcamera → lib,  share/libcamera → share
        string(REGEX MATCH "^[^/]+" _dst_parent "${_rel}")
        list(APPEND _dsts "${_dst_parent}")
    endforeach()

    set_property(TARGET "${target}" PROPERTY EP_RUNTIME_DIRS_SRC  "${_srcs}")
    set_property(TARGET "${target}" PROPERTY EP_RUNTIME_DIRS_DST  "${_dsts}")
    set_property(TARGET "${target}" PROPERTY EP_RUNTIME_NO_STRIP  "${_R_NO_STRIP}")
    set_property(TARGET "${target}" PROPERTY EP_RUNTIME_SIGN_KEY  "${_R_SIGN_KEY}")
endfunction()

# ---------------------------------------------------------------------------
# _ep_rt_traverse — рекурсивний обхід дерева INTERFACE_LINK_LIBRARIES.
#
# Використовує глобальні властивості як mutable-стан між рекурсивними
# викликами (PARENT_SCOPE поширюється тільки на один рівень вгору):
#   _EP_RT_VISITED       — вже оброблені targets (захист від циклів)
#   _EP_RT_FOUND_TARGETS — targets з EP_RUNTIME_DIRS_SRC
# ---------------------------------------------------------------------------
function(_ep_rt_traverse target)
    # Перевіряємо і маркуємо як відвіданий
    get_property(_vis GLOBAL PROPERTY _EP_RT_VISITED)
    list(FIND _vis "${target}" _i)
    if(NOT _i EQUAL -1)
        return()
    endif()
    list(APPEND _vis "${target}")
    set_property(GLOBAL PROPERTY _EP_RT_VISITED "${_vis}")

    # Перевіряємо цей target на наявність runtime ресурсів
    get_target_property(_srcs "${target}" EP_RUNTIME_DIRS_SRC)
    if(_srcs)
        get_property(_found GLOBAL PROPERTY _EP_RT_FOUND_TARGETS)
        list(FIND _found "${target}" _f)
        if(_f EQUAL -1)
            list(APPEND _found "${target}")
            set_property(GLOBAL PROPERTY _EP_RT_FOUND_TARGETS "${_found}")
        endif()
    endif()

    # Рекурсія в INTERFACE_LINK_LIBRARIES
    get_target_property(_iface "${target}" INTERFACE_LINK_LIBRARIES)
    if(NOT _iface)
        return()
    endif()
    foreach(_dep IN LISTS _iface)
        # Пропускаємо generator expressions, нетаргети і внутрішні _ep_sync_* обгортки
        if(_dep MATCHES "^\\$<" OR NOT TARGET "${_dep}" OR _dep MATCHES "^_ep_sync_")
            continue()
        endif()
        _ep_rt_traverse("${_dep}")
    endforeach()
endfunction()

# ---------------------------------------------------------------------------
# ep_collect_runtime_resources
# ---------------------------------------------------------------------------
function(ep_collect_runtime_resources main_target out_file_var)
    if(NOT TARGET "${main_target}")
        message(FATAL_ERROR "[RuntimeDeps] ep_collect_runtime_resources: '${main_target}' не є CMake target")
    endif()

    # Ініціалізуємо глобальний стан для цього обходу
    set_property(GLOBAL PROPERTY _EP_RT_VISITED "")
    set_property(GLOBAL PROPERTY _EP_RT_FOUND_TARGETS "")

    # Обхід стартує з LINK_LIBRARIES головного таргету
    get_target_property(_direct "${main_target}" LINK_LIBRARIES)
    if(NOT _direct)
        set(_direct "")
    endif()
    foreach(_dep IN LISTS _direct)
        if(_dep MATCHES "^\\$<" OR NOT TARGET "${_dep}" OR _dep MATCHES "^_ep_sync_")
            continue()
        endif()
        _ep_rt_traverse("${_dep}")
    endforeach()

    get_property(_rt_targets GLOBAL PROPERTY _EP_RT_FOUND_TARGETS)

    # Генеруємо cmake-файл із зібраними даними
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/_ep_cfg")
    set(_out "${CMAKE_BINARY_DIR}/_ep_cfg/runtime_resources_${main_target}.cmake")
    _ep_rt_write_file("${_rt_targets}" "${_out}")
    set(${out_file_var} "${_out}" PARENT_SCOPE)

    list(LENGTH _rt_targets _n)
    if(_n GREATER 0)
        message(STATUS "[RuntimeDeps] ${main_target}: ${_n} target(и) з runtime ресурсами")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# _ep_rt_write_file — серіалізація у cmake-файл для install_project.cmake
#
# Формат (index-based, для сумісності з -P скриптами):
#   EP_RT_COUNT        — кількість записів
#   EP_RT_SRC_<i>      — абсолютний шлях до директорії ресурсів у EXTERNAL_INSTALL_PREFIX
#   EP_RT_DST_<i>      — відносний destination parent (lib, share, etc)
#   EP_RT_NO_STRIP_<i> — TRUE/FALSE
#   EP_RT_SIGN_KEY_<i> — шлях до приватного ключа або порожній рядок
# ---------------------------------------------------------------------------
function(_ep_rt_write_file targets out_file)
    set(_idx 0)
    set(_body "")

    foreach(_tgt IN LISTS targets)
        get_target_property(_srcs     "${_tgt}" EP_RUNTIME_DIRS_SRC)
        get_target_property(_dsts     "${_tgt}" EP_RUNTIME_DIRS_DST)
        get_target_property(_no_strip "${_tgt}" EP_RUNTIME_NO_STRIP)
        get_target_property(_sign_key "${_tgt}" EP_RUNTIME_SIGN_KEY)

        # Нормалізуємо NOTFOUND → безпечні дефолти
        if(NOT _no_strip OR _no_strip MATCHES "NOTFOUND")
            set(_no_strip FALSE)
        endif()
        if(NOT _sign_key OR _sign_key MATCHES "NOTFOUND")
            set(_sign_key "")
        endif()

        list(LENGTH _srcs _n)
        if(NOT _n GREATER 0)
            continue()
        endif()
        math(EXPR _last "${_n} - 1")
        foreach(_j RANGE 0 ${_last})
            list(GET _srcs ${_j} _src)
            list(GET _dsts ${_j} _dst)
            string(APPEND _body
                "# [${_idx}] ${_tgt}\n"
                "set(EP_RT_SRC_${_idx}      \"${_src}\")\n"
                "set(EP_RT_DST_${_idx}      \"${_dst}\")\n"
                "set(EP_RT_NO_STRIP_${_idx} ${_no_strip})\n"
                "set(EP_RT_SIGN_KEY_${_idx} \"${_sign_key}\")\n"
            )
            math(EXPR _idx "${_idx} + 1")
        endforeach()
    endforeach()

    file(WRITE "${out_file}"
        "# Auto-generated by ep_collect_runtime_resources() — do not edit\n"
        "set(EP_RT_COUNT ${_idx})\n"
        "${_body}")
endfunction()
