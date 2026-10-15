set(MCU_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/material-color-utilities")
set(STB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/stb")

# Vendored quantizer, built without the project's warning flags.
add_library(burl-mcu-quantize STATIC
    "${MCU_DIR}/lab.cc"
    "${MCU_DIR}/utils.cc"
    "${MCU_DIR}/wsmeans.cc"
    "${MCU_DIR}/wu.cc"
)
target_include_directories(burl-mcu-quantize SYSTEM PUBLIC "${MCU_DIR}")
target_compile_options(burl-mcu-quantize PRIVATE -w)
set_target_properties(burl-mcu-quantize PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(burl-colour STATIC
    dynamic.cpp
    generator.cpp
    hct.cpp
    image.cpp
    palette.cpp
    resample.cpp
    spec.cpp
    thumbnail.cpp
)
target_include_directories(burl-colour PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/..")
target_include_directories(burl-colour SYSTEM PRIVATE "${STB_DIR}")
find_package(JPEG REQUIRED)
target_link_libraries(burl-colour PRIVATE burl-mcu-quantize Qt6::Gui JPEG::JPEG)
# Results must match the oracle bit for bit, so no FMA contraction.
target_compile_options(burl-colour PRIVATE -ffp-contract=off)
set_target_properties(burl-colour PROPERTIES POSITION_INDEPENDENT_CODE ON)
