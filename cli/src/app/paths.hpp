#pragma once

#include <qstring.h>

namespace burl {

// Every location the CLI reads or writes, resolved once from the environment.
struct Paths {
    QString configDir;
    QString dataDir;
    QString stateDir;
    QString cacheDir;
    QString picturesDir;

    QString burlConfigDir;
    QString burlStateDir;
    QString userConfig;
    QString cliData;
    QString templates;
    QString userTemplates;
    QString themeDir;
    QString themeLock;
    QString scheme;
    QString schemeData;
    QString schemeCache;
    QString wallpapersDir;
    QString wallpaperPath;
    QString wallpaperLink;
    QString wallpaperThumbnail;
    QString wallpapersCache;

    [[nodiscard]] static Paths fromEnvironment();
};

} // namespace burl
