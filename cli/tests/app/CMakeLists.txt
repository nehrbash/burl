get_filename_component(BURL_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(BURL_TEST_DATA_DIR "${BURL_ROOT}/cli/data")

add_executable(burl-theme-test theme_test.cpp)
target_link_libraries(burl-theme-test PRIVATE burl-app)
target_compile_definitions(burl-theme-test PRIVATE
    BURL_ORACLE_FILE="${BURL_ROOT}/tests/colour-oracle/themes.json"
    BURL_TEST_DATA_DIR="${BURL_TEST_DATA_DIR}"
)
add_test(NAME burl-app-theme COMMAND burl-theme-test)

add_executable(burl-cli-test cli_test.cpp)
target_link_libraries(burl-cli-test PRIVATE burl-app)
target_compile_definitions(burl-cli-test PRIVATE
    BURL_BINARY="$<TARGET_FILE:burl>"
    BURL_TEST_DATA_DIR="${BURL_TEST_DATA_DIR}"
)
add_test(NAME burl-app-cli COMMAND burl-cli-test)

add_executable(burl-scheme-test scheme_test.cpp)
target_link_libraries(burl-scheme-test PRIVATE burl-app)
target_compile_definitions(burl-scheme-test PRIVATE
    BURL_BINARY="$<TARGET_FILE:burl>"
    BURL_TEST_DATA_DIR="${BURL_TEST_DATA_DIR}"
)
add_test(NAME burl-app-scheme COMMAND burl-scheme-test)

add_executable(burl-hypr-test hypr_test.cpp)
target_link_libraries(burl-hypr-test PRIVATE burl-app)
target_compile_definitions(burl-hypr-test PRIVATE
    BURL_BINARY="$<TARGET_FILE:burl>"
    BURL_TEST_DATA_DIR="${BURL_TEST_DATA_DIR}"
)
add_test(NAME burl-app-hypr COMMAND burl-hypr-test)
