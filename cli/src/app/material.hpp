#pragma once

#include "scheme.hpp"

namespace burl {

// Generated palette for `image`, cached per image hash, variant, flavour and mode.
// Throws FileNotFound when the image does not exist.
Colours coloursForImage(const Paths& paths, const QString& image, const QString& variant, const QString& flavour,
                        const QString& mode);

} // namespace burl
