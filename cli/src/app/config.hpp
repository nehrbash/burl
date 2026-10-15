#pragma once

#include "json.hpp"
#include "paths.hpp"

namespace burl {

// The user's cli.json; missing or malformed files yield the defaults.
struct UserConfig {
    // The "theme" object: per-target enable switches.
    JsonValue theme = JsonValue::object();
    // Shell command run after a wallpaper change.
    QString postHook;
};

[[nodiscard]] UserConfig loadUserConfig(const Paths& paths);

} // namespace burl
