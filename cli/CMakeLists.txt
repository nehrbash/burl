# The `burl` command: colour scheme generation, wallpaper selection and
# application theming. The QML shell and bin/ scripts call it as a process.
find_package(Qt6 REQUIRED COMPONENTS Core Gui)

set(BURL_CLI_DATA_DIR "${CMAKE_INSTALL_PREFIX}/share/burl/cli"
    CACHE PATH "Installed scheme and template data")

add_subdirectory(src/colour)
add_subdirectory(src/app)
add_subdirectory(src/spotify-auth)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

install(DIRECTORY data/ DESTINATION "${BURL_CLI_DATA_DIR}")
