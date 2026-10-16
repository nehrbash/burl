cmake_minimum_required(VERSION 3.25)
project(burl-spotify-playlist-test LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Core Qml Network)
add_executable(spotify-playlist-test main.cpp
    ../../plugin/src/Burl/spotifysources.cpp
    ../../plugin/src/Burl/spotifysources.hpp)
target_link_libraries(spotify-playlist-test PRIVATE Qt6::Core Qt6::Qml Qt6::Network)
enable_testing()
add_test(NAME spotify-playlist COMMAND spotify-playlist-test)
