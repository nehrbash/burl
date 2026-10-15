get_filename_component(BURL_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

add_executable(burl-colour-test oracle_test.cpp)
target_include_directories(burl-colour-test PRIVATE "${CMAKE_CURRENT_LIST_DIR}/../../src/colour")
target_link_libraries(burl-colour-test PRIVATE burl-colour Qt6::Core)
target_compile_definitions(burl-colour-test PRIVATE BURL_ORACLE_DIR="${BURL_ROOT}/tests/colour-oracle")
add_test(NAME burl-colour-oracle COMMAND burl-colour-test)

add_executable(burl-thumbnail-test thumbnail_test.cpp)
target_link_libraries(burl-thumbnail-test PRIVATE burl-colour Qt6::Core)
target_compile_definitions(burl-thumbnail-test PRIVATE BURL_THUMBNAIL_DIR="${BURL_ROOT}/tests/colour-oracle/thumbnails")
add_test(NAME burl-colour-thumbnail COMMAND burl-thumbnail-test)
