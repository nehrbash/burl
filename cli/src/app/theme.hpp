#pragma once

#include "config.hpp"
#include "scheme.hpp"

namespace burl {

struct ThemeOptions {
    // Write the colour sequences to the open terminals.
    bool terminals = true;
    // Run external programs: Hyprland reload, sass, signals, spicetify.
    bool commands = true;
};

// Exclusive flock on the theme lock file for the lifetime of the object. A
// process must hold at most one: a second flock on another fd would deadlock.
class ThemeLock {
public:
    // Throws Error when the lock cannot be taken.
    explicit ThemeLock(const QString& path);
    ~ThemeLock();

    ThemeLock(const ThemeLock&) = delete;
    ThemeLock& operator=(const ThemeLock&) = delete;

private:
    int m_fd = -1;
};

// Renders every enabled target for `colours`. The caller holds the theme lock
// across loading, saving and applying the scheme. Per-target failures are
// logged and do not stop the others.
void applyColours(const ThemeLock& lock, const Paths& paths, const UserConfig& config, const Colours& colours,
                  const QString& mode, const ThemeOptions& options = {});

} // namespace burl
