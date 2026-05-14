# ConfigurePackaging.cmake
#
# Configures CPack for generating distribution packages (RPM, DEB, TGZ)
# for the Zeek ClickHouse plugin.

if (NOT COMMAND ConfigurePackaging)
    function(ConfigurePackaging version)
        set(CPACK_PACKAGE_NAME "zeek-plugin-clickhouse")
        set(CPACK_PACKAGE_VENDOR "Zeek ClickHouse Plugin Contributors")
        set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "ClickHouse input reader plugin for Zeek")
        set(CPACK_PACKAGE_DESCRIPTION "A Zeek plugin that provides an input reader for the Zeek Input Framework, allowing Zeek to read data directly from ClickHouse databases.")
        set(CPACK_PACKAGE_VERSION ${version})
        set(CPACK_PACKAGE_CONTACT "zeek-clickhouse@example.com")
        set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/example/zeek-clickhouse-plugin")

        # Parse version
        string(REGEX MATCH "^([0-9]+)\\.([0-9]+)\\.([0-9]+)" _ ${version})
        set(CPACK_PACKAGE_VERSION_MAJOR ${CMAKE_MATCH_1})
        set(CPACK_PACKAGE_VERSION_MINOR ${CMAKE_MATCH_2})
        set(CPACK_PACKAGE_VERSION_PATCH ${CMAKE_MATCH_3})

        # Resource files
        set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/COPYING")
        set(CPACK_RESOURCE_FILE_README "${CMAKE_CURRENT_SOURCE_DIR}/README.md")

        # Source package
        set(CPACK_SOURCE_GENERATOR "TGZ")
        set(CPACK_SOURCE_PACKAGE_FILE_NAME "${CPACK_PACKAGE_NAME}-${version}")
        set(CPACK_SOURCE_IGNORE_FILES
            "/\\\\.git/"
            "/\\\\.gitignore$"
            "/\\\\.github/"
            "/build/"
            "/cmake-build-.*/"
            "\\\\.swp$"
            "\\\\.swo$"
            "~$"
            "\\\\.DS_Store$"
            "/\\\\.vscode/"
            "/\\\\.idea/"
        )

        # Binary packages
        set(CPACK_GENERATOR "TGZ")

        # Determine system and architecture
        if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
            find_program(LSB_RELEASE lsb_release)
            if (LSB_RELEASE)
                execute_process(
                    COMMAND ${LSB_RELEASE} -is
                    OUTPUT_VARIABLE DISTRO_ID
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                )
                execute_process(
                    COMMAND ${LSB_RELEASE} -rs
                    OUTPUT_VARIABLE DISTRO_RELEASE
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                )
                string(TOLOWER "${DISTRO_ID}" DISTRO_ID_LOWER)

                # Enable RPM for RedHat-based systems
                if (DISTRO_ID_LOWER MATCHES "centos|rhel|fedora|rocky|almalinux")
                    list(APPEND CPACK_GENERATOR "RPM")
                endif()

                # Enable DEB for Debian-based systems
                if (DISTRO_ID_LOWER MATCHES "ubuntu|debian|mint")
                    list(APPEND CPACK_GENERATOR "DEB")
                endif()
            endif()
        endif()

        # DEB-specific settings
        set(CPACK_DEBIAN_PACKAGE_SECTION "net")
        set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")
        set(CPACK_DEBIAN_PACKAGE_DEPENDS "zeek (>= 5.0), libclickhouse-cpp-lib")
        set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Zeek ClickHouse Plugin Contributors <zeek-clickhouse@example.com>")
        set(CPACK_DEBIAN_FILE_NAME "DEB-DEFAULT")
        set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)

        # RPM-specific settings
        set(CPACK_RPM_PACKAGE_GROUP "Applications/Internet")
        set(CPACK_RPM_PACKAGE_LICENSE "BSD-3-Clause")
        set(CPACK_RPM_PACKAGE_REQUIRES "zeek >= 5.0, clickhouse-cpp")
        set(CPACK_RPM_FILE_NAME "RPM-DEFAULT")
        set(CPACK_RPM_PACKAGE_AUTOREQ ON)
        set(CPACK_RPM_PACKAGE_AUTOPROV ON)

        # Package file naming
        set(CPACK_PACKAGE_FILE_NAME
            "${CPACK_PACKAGE_NAME}-${version}-${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}")

        # Installation directories
        if (NOT CPACK_PACKAGING_INSTALL_PREFIX)
            set(CPACK_PACKAGING_INSTALL_PREFIX "/usr/local")
        endif()

        # Components
        set(CPACK_COMPONENTS_ALL plugin scripts documentation)
        set(CPACK_COMPONENT_PLUGIN_DISPLAY_NAME "Plugin Library")
        set(CPACK_COMPONENT_PLUGIN_DESCRIPTION "The ClickHouse input reader plugin library")
        set(CPACK_COMPONENT_PLUGIN_REQUIRED ON)

        set(CPACK_COMPONENT_SCRIPTS_DISPLAY_NAME "Zeek Scripts")
        set(CPACK_COMPONENT_SCRIPTS_DESCRIPTION "Zeek scripts for using the ClickHouse plugin")
        set(CPACK_COMPONENT_SCRIPTS_DEPENDS plugin)

        set(CPACK_COMPONENT_DOCUMENTATION_DISPLAY_NAME "Documentation")
        set(CPACK_COMPONENT_DOCUMENTATION_DESCRIPTION "Documentation and examples")

        # Archive settings
        set(CPACK_ARCHIVE_COMPONENT_INSTALL ON)

        # Debugging output
        message(STATUS "Package configuration:")
        message(STATUS "  Name: ${CPACK_PACKAGE_NAME}")
        message(STATUS "  Version: ${version}")
        message(STATUS "  Generators: ${CPACK_GENERATOR}")
        message(STATUS "  Install prefix: ${CPACK_PACKAGING_INSTALL_PREFIX}")

        include(CPack)
    endfunction()
endif()
