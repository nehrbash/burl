#pragma once

#include "scheme.hpp"

#include <optional>

namespace burl {

struct WallpaperPalette {
    QString name;
    QString flavour;
    QString mode;
    QString variant;
    Colours colours;
};

struct RandomOptions {
    QString directory;
    bool noFilter = false;
    double threshold = 0.8;
    bool noSmart = false;
};

// The current wallpaper path, if one is set.
std::optional<QString> currentWallpaper(const Paths& paths);

bool isValidImage(const QString& path);

WallpaperPalette coloursForWallpaper(const Paths& paths, const QString& wall, bool noSmart);
void setWallpaper(const Paths& paths, const QString& wall, bool noSmart);
void setRandomWallpaper(const Paths& paths, const RandomOptions& options);

} // namespace burl
