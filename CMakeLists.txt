cmake_minimum_required(VERSION 3.15)

project(ZeekPluginClickHouse)

# ---------------------------------------------------------------------------
# CMake module path
# ---------------------------------------------------------------------------

# Local cmake/ helpers first (ConfigurePackaging, etc.)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# Zeek's own cmake helpers – prefer path reported by zeek-config
find_program(ZEEK_CONFIG zeek-config
             HINTS ENV PATH
                   /opt/zeek/bin
                   /usr/local/zeek/bin
                   /usr/bin)

if (ZEEK_CONFIG)
    execute_process(COMMAND ${ZEEK_CONFIG} --cmake_dir
                    OUTPUT_VARIABLE ZEEK_CMAKE_DIR
                    OUTPUT_STRIP_TRAILING_WHITESPACE)
    if (ZEEK_CMAKE_DIR AND EXISTS "${ZEEK_CMAKE_DIR}")
        list(APPEND CMAKE_MODULE_PATH "${ZEEK_CMAKE_DIR}")
    endif ()
endif ()

# Fallback: well-known Zeek cmake locations
foreach (_candidate
        "${ZEEK_ROOT_DIR}/share/zeek/cmake"
        "/opt/zeek/share/zeek/cmake"
        "/usr/local/zeek/share/zeek/cmake"
        "/usr/share/zeek/cmake")
    if (EXISTS "${_candidate}" AND NOT "${_candidate}" IN_LIST CMAKE_MODULE_PATH)
        list(APPEND CMAKE_MODULE_PATH "${_candidate}")
    endif ()
endforeach ()

include(cmake/ZeekPlugin.cmake)

# ---------------------------------------------------------------------------
# ClickHouse C++ client library
# ---------------------------------------------------------------------------

# Prefer the shared library so that -fPIC is not a concern.
# A static library (.a) also works, but ONLY if it was compiled with
# -DCMAKE_POSITION_INDEPENDENT_CODE=ON; otherwise the linker will fail
# with "recompile with -fPIC" when building the plugin shared object.
find_library(CLICKHOUSE_CPP_SHARED_LIB
             NAMES clickhouse-cpp-lib
             PATHS /usr/local/lib /usr/lib
             NO_DEFAULT_PATH)

find_library(CLICKHOUSE_CPP_STATIC_LIB
             NAMES libclickhouse-cpp-lib.a clickhouse-cpp-lib-static clickhouse-cpp-lib
             PATHS /usr/local/lib /usr/lib
             NO_DEFAULT_PATH)

if (CLICKHOUSE_CPP_SHARED_LIB)
    set(CLICKHOUSE_CPP_LIB "${CLICKHOUSE_CPP_SHARED_LIB}")
    message(STATUS "ClickHouse shared library: ${CLICKHOUSE_CPP_LIB}")
elseif (CLICKHOUSE_CPP_STATIC_LIB)
    set(CLICKHOUSE_CPP_LIB "${CLICKHOUSE_CPP_STATIC_LIB}")
    message(STATUS "ClickHouse static library: ${CLICKHOUSE_CPP_LIB}")
    message(STATUS "  Note: static library must have been compiled with "
                   "-DCMAKE_POSITION_INDEPENDENT_CODE=ON. "
                   "If the link step fails with 'recompile with -fPIC', rebuild "
                   "clickhouse-cpp:\n"
                   "    cmake .. -DCMAKE_BUILD_TYPE=Release "
                   "-DCMAKE_POSITION_INDEPENDENT_CODE=ON")
else ()
    message(FATAL_ERROR
        "ClickHouse C++ client library not found.\n"
        "Install from https://github.com/ClickHouse/clickhouse-cpp, then rebuild with:\n"
        "  cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON\n"
        "  make -j$(nproc) && sudo make install")
endif ()

find_path(CLICKHOUSE_CPP_INCLUDE
          NAMES clickhouse/client.h
          PATHS /usr/local/include /usr/include
          REQUIRED)

message(STATUS "ClickHouse library:  ${CLICKHOUSE_CPP_LIB}")
message(STATUS "ClickHouse includes: ${CLICKHOUSE_CPP_INCLUDE}")

# ---------------------------------------------------------------------------
# Abseil (transitive header dependency of clickhouse-cpp)
#
# clickhouse-cpp headers pull in absl/numeric/int128.h and others.
# Strategy:
#   1. find_package(absl)  — works when absl is installed with CMake support
#   2. Manual find_path    — fallback for system packages without CMake config
# ---------------------------------------------------------------------------

find_package(absl QUIET)

if (absl_FOUND)
    message(STATUS "Abseil found via CMake config")
    set(_absl_include_dirs "")      # propagated automatically via targets
    set(_absl_link_targets
        absl::int128
        absl::base
        absl::strings
        absl::throw_delegate
        absl::raw_logging_internal)
else ()
    message(STATUS "Abseil CMake config not found – searching for headers manually")

    find_path(ABSL_INCLUDE_DIR
              NAMES absl/numeric/int128.h
              PATHS
                  /usr/local/include
                  /usr/include
                  /opt/local/include
                  /opt/homebrew/include
              DOC "Directory containing the absl/ header tree")

    if (NOT ABSL_INCLUDE_DIR)
        message(FATAL_ERROR
            "Abseil headers not found (absl/numeric/int128.h).\n"
            "Abseil is a required transitive dependency of clickhouse-cpp.\n"
            "Install it with one of:\n"
            "  Ubuntu/Debian : sudo apt-get install libabsl-dev\n"
            "  CentOS/RHEL   : sudo dnf install abseil-cpp-devel\n"
            "  macOS         : brew install abseil\n"
            "  From source   : https://github.com/abseil/abseil-cpp\n"
            "Or pass -DABSL_INCLUDE_DIR=<path> on the cmake command line.")
    endif ()

    message(STATUS "Abseil headers (manual): ${ABSL_INCLUDE_DIR}")
    set(_absl_include_dirs "${ABSL_INCLUDE_DIR}")

    # Try to locate individual absl static libs.  If clickhouse-cpp is a
    # shared library the absl symbols are already inside it and these are
    # optional; we skip silently when absent.
    foreach (_alib
            absl_int128
            absl_base
            absl_strings
            absl_throw_delegate
            absl_raw_logging_internal)
        find_library(_found_${_alib} NAMES ${_alib} PATHS /usr/local/lib /usr/lib)
        if (_found_${_alib})
            list(APPEND _absl_link_targets "${_found_${_alib}}")
        endif ()
    endforeach ()
endif ()

# ---------------------------------------------------------------------------
# Plugin definition
# ---------------------------------------------------------------------------

zeek_plugin_begin(VNET ClickHouse)
zeek_plugin_cc(src/Plugin.cc)
zeek_plugin_cc(src/ClickHouse.cc)
zeek_plugin_dist_files(README.md COPYING VERSION)
zeek_plugin_end()

# Include paths
target_include_directories(${_plugin_lib} PRIVATE
    "${CLICKHOUSE_CPP_INCLUDE}"
    ${_absl_include_dirs})          # empty when absl_FOUND (targets carry it)

# Link libraries
target_link_libraries(${_plugin_lib} PRIVATE
    "${CLICKHOUSE_CPP_LIB}"
    ${_absl_link_targets})

# Require C++20 — Zeek 6.x headers use std::span and concepts
set_target_properties(${_plugin_lib} PROPERTIES
    CXX_STANDARD          20
    CXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# Packaging (only when built as the top-level project)
# ---------------------------------------------------------------------------

file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" VERSION LIMIT_COUNT 1)

if ("${PROJECT_SOURCE_DIR}" STREQUAL "${CMAKE_SOURCE_DIR}")
    include(ConfigurePackaging)
    ConfigurePackaging(${VERSION})
endif ()
