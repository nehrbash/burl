find_package(Qt6 REQUIRED COMPONENTS Core Network)

add_executable(burl-spotify-auth main.cpp)
set_target_properties(burl-spotify-auth PROPERTIES AUTOMOC ON)
target_link_libraries(burl-spotify-auth PRIVATE Qt6::Core Qt6::Network)

install(TARGETS burl-spotify-auth RUNTIME DESTINATION bin)
