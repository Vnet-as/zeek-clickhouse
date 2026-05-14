# Provides functions for configuring a Zeek plugin.
#
# Include-directory detection strategy (in order of preference):
#   1. ZEEK_INCLUDE_DIR set explicitly by the caller / environment
#   2. $(zeek-config --prefix)/include  — most reliable for binary installs
#   3. $(zeek-config --include_dir)     — exists in some versions; validate it
#   4. ${ZEEK_ROOT_DIR}/include         — last-resort fallback

if ( NOT ZEEK_PLUGIN_CMAKE_INCLUDED )
    set(ZEEK_PLUGIN_CMAKE_INCLUDED true)

    # ------------------------------------------------------------------
    # Locate zeek-config
    # ------------------------------------------------------------------
    if ( NOT ZEEK_CONFIG )
        find_program(ZEEK_CONFIG zeek-config
                     HINTS ENV PATH
                           /opt/zeek/bin
                           /usr/local/zeek/bin
                           /usr/bin)
    endif ()

    # ------------------------------------------------------------------
    # ZEEK_ROOT_DIR  (installation prefix, e.g. /opt/zeek)
    # ------------------------------------------------------------------
    if ( NOT ZEEK_ROOT_DIR )
        if ( DEFINED ENV{ZEEK_ROOT_DIR} )
            set(ZEEK_ROOT_DIR "$ENV{ZEEK_ROOT_DIR}")
        elseif ( ZEEK_CONFIG )
            # --prefix is the installed prefix; --zeek_dist points at the
            # *source tree* and is unreliable for locating installed headers.
            execute_process(COMMAND ${ZEEK_CONFIG} --prefix
                            OUTPUT_VARIABLE ZEEK_ROOT_DIR
                            OUTPUT_STRIP_TRAILING_WHITESPACE
                            RESULT_VARIABLE _rc)
            if ( NOT _rc EQUAL 0 OR NOT ZEEK_ROOT_DIR )
                message(FATAL_ERROR
                    "zeek-config --prefix failed. "
                    "Please set ZEEK_ROOT_DIR to your Zeek installation prefix.")
            endif ()
        endif ()
    endif ()

    if ( NOT ZEEK_ROOT_DIR )
        message(FATAL_ERROR
            "Cannot determine Zeek installation prefix. "
            "Add zeek-config to PATH or set -DZEEK_ROOT_DIR=<prefix>.")
    endif ()

    # ------------------------------------------------------------------
    # ZEEK_PLUGIN_DIR
    # ------------------------------------------------------------------
    if ( NOT ZEEK_PLUGIN_DIR )
        if ( DEFINED ENV{ZEEK_PLUGIN_DIR} )
            set(ZEEK_PLUGIN_DIR "$ENV{ZEEK_PLUGIN_DIR}")
        elseif ( ZEEK_CONFIG )
            execute_process(COMMAND ${ZEEK_CONFIG} --plugin_dir
                            OUTPUT_VARIABLE ZEEK_PLUGIN_DIR
                            OUTPUT_STRIP_TRAILING_WHITESPACE)
        endif ()
        if ( NOT ZEEK_PLUGIN_DIR )
            set(ZEEK_PLUGIN_DIR "${ZEEK_ROOT_DIR}/lib/zeek/plugins")
        endif ()
    endif ()

    # ------------------------------------------------------------------
    # ZEEK_INCLUDE_DIR
    # Must be the directory that *contains* the zeek/ sub-directory, i.e.
    # the one passed to -I so that #include <zeek/plugin/Plugin.h> resolves.
    # ------------------------------------------------------------------
    if ( NOT ZEEK_INCLUDE_DIR )

        # Strategy 1: ${prefix}/include  (canonical binary-install layout)
        set(_candidate "${ZEEK_ROOT_DIR}/include")
        if ( EXISTS "${_candidate}/zeek/plugin/Plugin.h" )
            set(ZEEK_INCLUDE_DIR "${_candidate}")
        endif ()

        # Strategy 2: zeek-config --include_dir (present in some versions)
        if ( NOT ZEEK_INCLUDE_DIR AND ZEEK_CONFIG )
            execute_process(COMMAND ${ZEEK_CONFIG} --include_dir
                            OUTPUT_VARIABLE _inc
                            OUTPUT_STRIP_TRAILING_WHITESPACE
                            RESULT_VARIABLE _rc)
            if ( _rc EQUAL 0 AND _inc )
                if ( EXISTS "${_inc}/zeek/plugin/Plugin.h" )
                    # Points at the right parent directory already
                    set(ZEEK_INCLUDE_DIR "${_inc}")
                elseif ( EXISTS "${_inc}/plugin/Plugin.h" )
                    # Points *inside* the zeek/ subdir — step one level up
                    get_filename_component(ZEEK_INCLUDE_DIR "${_inc}" DIRECTORY)
                endif ()
            endif ()
        endif ()

        # Strategy 3: derive from --zeek_dist (source-tree / dev builds)
        if ( NOT ZEEK_INCLUDE_DIR AND ZEEK_CONFIG )
            execute_process(COMMAND ${ZEEK_CONFIG} --zeek_dist
                            OUTPUT_VARIABLE _dist
                            OUTPUT_STRIP_TRAILING_WHITESPACE
                            RESULT_VARIABLE _rc)
            if ( _rc EQUAL 0 AND _dist )
                foreach (_try "${_dist}/include" "${_dist}/src")
                    if ( EXISTS "${_try}/zeek/plugin/Plugin.h" )
                        set(ZEEK_INCLUDE_DIR "${_try}")
                        break()
                    endif ()
                endforeach ()
            endif ()
        endif ()

        # Strategy 4: hard-coded well-known locations
        if ( NOT ZEEK_INCLUDE_DIR )
            foreach (_try
                    "/opt/zeek/include"
                    "/usr/local/zeek/include"
                    "/usr/include/zeek"
                    "/usr/local/include/zeek")
                if ( EXISTS "${_try}/zeek/plugin/Plugin.h" )
                    set(ZEEK_INCLUDE_DIR "${_try}")
                    break()
                endif ()
            endforeach ()
        endif ()

        if ( NOT ZEEK_INCLUDE_DIR )
            message(FATAL_ERROR
                "Could not locate Zeek headers (looked for zeek/plugin/Plugin.h).\n"
                "Tried prefix=${ZEEK_ROOT_DIR}/include and several fallbacks.\n"
                "Set -DZEEK_INCLUDE_DIR=<path> explicitly.")
        endif ()
    endif ()

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    message(STATUS "Zeek prefix:          ${ZEEK_ROOT_DIR}")
    message(STATUS "Zeek plugin dir:      ${ZEEK_PLUGIN_DIR}")
    message(STATUS "Zeek include dir:     ${ZEEK_INCLUDE_DIR}")

    # ------------------------------------------------------------------
    # Plugin macros
    # ------------------------------------------------------------------

    macro(zeek_plugin_begin ns name)
        set(_plugin_name        "${ns}::${name}")
        set(_plugin_name_canon  "${ns}_${name}")
        set(_plugin_lib         "zeek-plugin-${_plugin_name_canon}")
        set(_plugin_dist        "${CMAKE_CURRENT_BINARY_DIR}/${_plugin_name_canon}")
        set(_plugin_srcs)
        set(_plugin_bifs)
        set(_plugin_dist_files)
        message(STATUS "Configuring plugin ${_plugin_name}")
    endmacro()

    macro(zeek_plugin_cc src)
        list(APPEND _plugin_srcs "${src}")
    endmacro()

    # zeek_plugin_bif: kept for completeness; not used by this plugin.
    macro(zeek_plugin_bif bif)
        list(APPEND _plugin_bifs "${bif}")

        get_filename_component(bif_basename "${bif}" NAME_WE)
        set(bif_output_cc "${CMAKE_CURRENT_BINARY_DIR}/${bif_basename}.bif.cc")
        set(bif_output_h  "${CMAKE_CURRENT_BINARY_DIR}/${bif_basename}.bif.h")

        add_custom_command(
            OUTPUT  ${bif_output_cc} ${bif_output_h}
            COMMAND bifcl "${CMAKE_CURRENT_SOURCE_DIR}/${bif}"
            DEPENDS "${bif}"
            WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
            COMMENT "Generating BIF files from ${bif}"
        )

        list(APPEND _plugin_srcs "${bif_output_cc}")
    endmacro()

    macro(zeek_plugin_dist_files)
        foreach (file ${ARGN})
            list(APPEND _plugin_dist_files "${file}")
        endforeach ()
    endmacro()

    macro(zeek_plugin_end)
        add_library(${_plugin_lib} MODULE ${_plugin_srcs})

        # Build the platform suffix Zeek expects, e.g. "linux-x86_64".
        string(TOLOWER "${CMAKE_SYSTEM_NAME}" _sys_name_lower)
        set(_plugin_output_name "${_plugin_name_canon}.${_sys_name_lower}-${CMAKE_SYSTEM_PROCESSOR}")

        set_target_properties(${_plugin_lib} PROPERTIES
            PREFIX ""
            OUTPUT_NAME                 "${_plugin_output_name}"
            LIBRARY_OUTPUT_DIRECTORY    "${_plugin_dist}/lib"
            CXX_STANDARD                20
            CXX_STANDARD_REQUIRED       ON
        )

        # ZEEK_INCLUDE_DIR already points at the directory that contains the
        # zeek/ sub-tree (e.g. /opt/zeek/include), so a single entry is enough.
        # Do NOT add ${ZEEK_INCLUDE_DIR}/zeek — that would make bare includes
        # like <plugin/Plugin.h> accidentally work and mask real path errors.
        target_include_directories(${_plugin_lib} PRIVATE
            "${ZEEK_INCLUDE_DIR}"
            "${CMAKE_CURRENT_SOURCE_DIR}/src"
            "${CMAKE_CURRENT_BINARY_DIR}"
        )

        target_compile_options(${_plugin_lib} PRIVATE
            -Wall -Wextra -Wno-unused-parameter
        )

        # Create the __zeek_plugin__ marker file that Zeek uses to discover plugins.
        # It must sit at the root of the plugin directory and contain the
        # fully-qualified plugin name (e.g. "VNET::ClickHouse").
        file(WRITE "${_plugin_dist}/__zeek_plugin__" "${_plugin_name}\n")

        foreach (file ${_plugin_dist_files})
            configure_file("${file}" "${_plugin_dist}/${file}" COPYONLY)
        endforeach ()

        if ( EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/scripts" )
            file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/scripts"
                 DESTINATION "${_plugin_dist}")
        endif ()

        install(DIRECTORY "${_plugin_dist}/"
                DESTINATION "${ZEEK_PLUGIN_DIR}/${_plugin_name_canon}")

        message(STATUS
            "Plugin ${_plugin_name} will install to: "
            "${ZEEK_PLUGIN_DIR}/${_plugin_name_canon}")
    endmacro()

endif () # ZEEK_PLUGIN_CMAKE_INCLUDED
