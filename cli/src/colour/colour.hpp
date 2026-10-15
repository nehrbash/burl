#pragma once

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

// Colour engine for the `burl` command. Output is pinned bit for bit by
// tests/colour-oracle.
namespace burl::colour {

struct Selection {
    std::string variant; // tonalspot, vibrant, expressive, fidelity, fruitsalad,
                         // monochrome, neutral, rainbow, content
    std::string flavour; // default or hard
    std::string mode;    // light or dark
};

// (name, "RRGGBB") pairs in generator order.
using Colours = std::vector<std::pair<std::string, std::string>>;

// Throws std::domain_error for achromatic seeds with hue-dependent variants.
Colours generate(const Selection& selection, std::uint32_t sourceArgb);

struct Image {
    int width = 0;
    int height = 0;
    std::vector<std::uint32_t> argb; // row-major, alpha preserved
};

// Decodes as Pillow does for colourfulness and the smart mode, and as the
// quantizer's own loader does for scoring. Throws std::runtime_error.
Image loadImage(const std::string& path);

// Seed colour of an image file: Celebi quantisation to 128 colours, scored.
std::uint32_t scoreImage(const std::string& path);

// Hasler-Süsstrunk colourfulness and the variant it selects.
double colourfulness(const Image& image);
std::string variantFor(const Image& image);

// Light or dark from the tone of the image's Lanczos 1x1 reduction.
std::string modeFor(const Image& image);

// Pillow's `convert("RGB").thumbnail((128, 128), Image.NEAREST)` saved as a default JPEG, byte for byte. Throws
// std::runtime_error when the image cannot be decoded.
std::vector<std::uint8_t> thumbnailJpeg(const std::string& path);

} // namespace burl::colour
