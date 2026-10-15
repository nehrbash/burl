add_library(burl-app STATIC
    cli.cpp
    config.cpp
    hypr.cpp
    json.cpp
    material.cpp
    notify.cpp
    paths.cpp
    scheme.cpp
    theme.cpp
    util.cpp
    wallpaper.cpp
)

target_include_directories(burl-app PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}/..")
target_compile_definitions(burl-app PRIVATE
    BURL_CLI_DATA_DIR="${BURL_CLI_DATA_DIR}"
    BURL_VERSION="${PROJECT_VERSION}"
    BURL_GIT_REVISION="${GIT_REVISION}"
)
target_link_libraries(burl-app PUBLIC Qt6::Core Qt6::Gui)

target_link_libraries(burl-app PUBLIC burl-colour)

add_executable(burl main.cpp)
target_link_libraries(burl PRIVATE burl-app)

install(TARGETS burl RUNTIME DESTINATION bin)
