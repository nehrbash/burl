cmake_minimum_required(VERSION 3.25)
project(burl-steam-library-test LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Core Qml Concurrent)
add_executable(steam-library-test main.cpp
    ../../plugin/src/Burl/Services/steamlibrary.cpp
    ../../plugin/src/Burl/Services/steamlibrary.hpp)
target_link_libraries(steam-library-test PRIVATE Qt6::Core Qt6::Qml Qt6::Concurrent)
enable_testing()
add_test(NAME steam-library COMMAND steam-library-test)
