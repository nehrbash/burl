#include "paths.hpp"

#include "json.hpp"
#include "util.hpp"

#include <qdir.h>
#include <qfileinfo.h>

namespace burl {

namespace {

QString environment(const char* name, const QString& fallback) {
    const auto value = qEnvironmentVariable(name);
    return value.isEmpty() ? fallback : value;
}

QString expandUser(const QString& path) {
    if (path == u"~") {
        return QDir::homePath();
    }
    if (path.startsWith(u"~/")) {
        return QDir::homePath() + path.mid(1);
    }
    return path;
}

// Order: QS_WALLPAPERS_DIR / BURL_WALLPAPERS_DIR, then `paths.wallpaperDir`
// from the shell's shell.json, then $XDG_PICTURES_DIR/Wallpapers.
QString resolveWallpapersDir(const QString& burlConfigDir, const QString& picturesDir) {
    for (const auto* name : {"QS_WALLPAPERS_DIR", "BURL_WALLPAPERS_DIR"}) {
        const auto value = qEnvironmentVariable(name);
        if (!value.isEmpty()) {
            return value;
        }
    }

    try {
        const auto data = parseJson(readFile(burlConfigDir + u"/shell.json").toStdString());
        if (const auto* paths = data.find("paths"); paths && paths->isObject()) {
            if (const auto* dir = paths->find("wallpaperDir"); dir && dir->isString() && !dir->asString().empty()) {
                return expandUser(QString::fromStdString(dir->asString()));
            }
        }
    } catch (const std::exception&) {
    }

    return picturesDir + u"/Wallpapers";
}

} // namespace

Paths Paths::fromEnvironment() {
    const auto home = QDir::homePath();

    Paths p;
    p.configDir = environment("XDG_CONFIG_HOME", home + u"/.config");
    p.dataDir = environment("XDG_DATA_HOME", home + u"/.local/share");
    p.stateDir = environment("XDG_STATE_HOME", home + u"/.local/state");
    p.cacheDir = environment("XDG_CACHE_HOME", home + u"/.cache");
    p.picturesDir = environment("XDG_PICTURES_DIR", home + u"/Pictures");

    p.burlConfigDir = p.configDir + u"/burl";
    p.burlStateDir = p.stateDir + u"/burl";
    const auto cache = p.cacheDir + u"/burl";

    p.userConfig = p.burlConfigDir + u"/cli.json";
    p.cliData = environment("BURL_CLI_DATA_DIR", QStringLiteral(BURL_CLI_DATA_DIR));
    p.templates = p.cliData + u"/templates";
    p.userTemplates = p.burlConfigDir + u"/templates";
    p.themeDir = p.burlStateDir + u"/theme";
    p.themeLock = p.burlStateDir + u"/theme.lock";

    p.scheme = p.burlStateDir + u"/scheme.json";
    p.schemeData = p.cliData + u"/schemes";
    p.schemeCache = cache + u"/schemes";

    p.wallpapersDir = resolveWallpapersDir(p.burlConfigDir, p.picturesDir);
    p.wallpaperPath = p.burlStateDir + u"/wallpaper/path.txt";
    p.wallpaperLink = p.burlStateDir + u"/wallpaper/current";
    p.wallpaperThumbnail = p.burlStateDir + u"/wallpaper/thumbnail.jpg";
    p.wallpapersCache = cache + u"/wallpapers";
    return p;
}

} // namespace burl
