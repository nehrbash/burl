#pragma once

#include <array>
#include <cstdint>
#include <vector>

namespace burl::colour {

// Pillow's `Image.thumbnail((1, 1), Image.LANCZOS)` of an RGB image, read back at (0, 0). `rgb` holds width * height
// packed R, G, B bytes in row-major order.
std::array<int, 3> lanczosMeanPixel(const std::vector<std::uint8_t>& rgb, int width, int height);

} // namespace burl::colour
