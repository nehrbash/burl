#include "wallpaper.hpp"

#include "colour/colour.hpp"
#include "config.hpp"
#include "hypr.hpp"
#include "material.hpp"
#include "theme.hpp"
#include "util.hpp"

#include <algorithm>
#include <cerrno>
#include <climits>
#include <cstring>
#include <exception>
#include <iterator>
#include <unistd.h>
#include <vector>
#include <qdiriterator.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qimagereader.h>
#include <qjsonobject.h>
#include <qrandom.h>

using Qt::StringLiterals::operator""_s;

namespace burl {

namespace {

QString thumbnailFor(const QString& wall, const QString& cache) {
    const auto thumb = cache + u"/thumbnail.jpg";

    if (!QFileInfo::exists(thumb)) {
        if (!QFileInfo::exists(wall)) {
            throw FileNotFound(wall + u": No such file or directory"_s);
        }

        std::vector<std::uint8_t> bytes;
        try {
            bytes = colour::thumbnailJpeg(wall.toStdString());
        } catch (const std::exception& error) {
            throw Error(u"%1: %2"_s.arg(wall, QString::fromStdString(error.what())));
        }

        writeFileAtomic(thumb, QByteArray(reinterpret_cast<const char*>(bytes.data()), static_cast<qsizetype>(bytes.size())));
    }

    return thumb;
}

struct SmartOptions {
    QString variant;
    QString mode;
};

SmartOptions smartOptions(const QString& wall, const QString& cache) {
    const auto optsCache = cache + u"/smart.json";

    try {
        const auto json = parseJson(readFile(optsCache).toStdString());
        const auto* variant = json.find("variant");
        const auto* mode = json.find("mode");
        if (variant && variant->isString() && mode && mode->isString()) {
            return {QString::fromStdString(variant->asString()), QString::fromStdString(mode->asString())};
        }
    } catch (const Error&) {
    } catch (const JsonError&) {
    }

    const auto image = colour::loadImage(thumbnailFor(wall, cache).toStdString());
    SmartOptions options{QString::fromStdString(colour::variantFor(image)),
                         QString::fromStdString(colour::modeFor(image))};

    auto json = JsonValue::object();
    json.set("variant", JsonValue::string(options.variant.toStdString()));
    json.set("mode", JsonValue::string(options.mode.toStdString()));
    writeFileAtomic(optsCache, QByteArray::fromStdString(dumpJson(json)));
    return options;
}

bool checkWall(const QString& wall, const QSize& filter, double threshold) {
    const auto size = QImageReader(wall).size();
    return size.isValid() && size.width() >= filter.width() * threshold && size.height() >= filter.height() * threshold;
}

QStringList listWallpapers(const RandomOptions& options) {
    const QFileInfo directory(options.directory);
    if (!directory.isDir()) {
        return {};
    }

    QStringList walls;
    QDirIterator it(options.directory, QDir::Files | QDir::Dirs | QDir::Hidden | QDir::NoDotAndDotDot,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const auto path = it.next();
        if (isValidImage(path)) {
            walls.append(path);
        }
    }

    if (options.noFilter) {
        return walls;
    }

    const auto monitors = hyprMonitors();
    if (monitors.isEmpty()) {
        throw Error(u"Hyprland reported no monitors"_s);
    }
    QSize filter(INT_MAX, INT_MAX);
    for (const auto& monitor : monitors) {
        const auto object = monitor.toObject();
        filter.setWidth(std::min(filter.width(), object.value(u"width"_s).toInt()));
        filter.setHeight(std::min(filter.height(), object.value(u"height"_s).toInt()));
    }

    QStringList filtered;
    std::copy_if(walls.begin(), walls.end(), std::back_inserter(filtered),
                 [&](const QString& wall) { return checkWall(wall, filter, options.threshold); });
    return filtered;
}

void replaceSymlink(const QString& link, const QString& target) {
    if (!QDir().mkpath(QFileInfo(link).absolutePath())) {
        throw Error(link + u": cannot create directory"_s);
    }
    const auto linkPath = QFile::encodeName(link);
    const auto temporary = linkPath + ".tmp";
    ::unlink(temporary.constData());
    if (::symlink(QFile::encodeName(target).constData(), temporary.constData()) != 0
        || ::rename(temporary.constData(), linkPath.constData()) != 0) {
        const auto message = link + u": "_s + QString::fromLocal8Bit(std::strerror(errno));
        ::unlink(temporary.constData());
        throw Error(message);
    }
}

void runPostHook(const QString& hook, const QString& wall) {
    if (hook.isEmpty()) {
        return;
    }

    auto environment = QProcessEnvironment::systemEnvironment();
    environment.insert(u"WALLPAPER_PATH"_s, wall);

    QProcess process;
    process.setProcessEnvironment(environment);
    process.setProcessChannelMode(QProcess::ForwardedOutputChannel);
    process.setStandardInputFile(QProcess::nullDevice());
    process.setStandardErrorFile(QProcess::nullDevice());
    process.start(u"/bin/sh"_s, {u"-c"_s, hook});
    if (process.waitForStarted()) {
        process.waitForFinished(-1);
    }
}

QString canonicalPath(const QString& path) {
    const auto canonical = QFileInfo(path).canonicalFilePath();
    return canonical.isEmpty() ? QDir::cleanPath(QFileInfo(path).absoluteFilePath()) : canonical;
}

} // namespace

std::optional<QString> currentWallpaper(const Paths& paths) {
    try {
        return QString::fromUtf8(readFile(paths.wallpaperPath));
    } catch (const Error&) {
        return std::nullopt;
    }
}

bool isValidImage(const QString& path) {
    static const QStringList suffixes = {u".jpg"_s, u".jpeg"_s, u".png"_s, u".webp"_s, u".tif"_s, u".tiff"_s};
    return QFileInfo(path).isFile() && suffixes.contains(pathSuffix(path));
}

WallpaperPalette coloursForWallpaper(const Paths& paths, const QString& wall, bool noSmart) {
    auto scheme = Scheme::load(paths);
    const auto cache = paths.wallpapersCache + u"/" + sha256File(wall);

    auto flavour = scheme.flavour();
    auto mode = scheme.mode();
    auto variant = scheme.variant();
    if (!noSmart) {
        const auto smart = smartOptions(wall, cache);
        mode = smart.mode;
        variant = smart.variant;
    }

    const auto thumb = thumbnailFor(wall, cache);
    return {u"dynamic"_s, flavour, mode, variant, coloursForImage(paths, thumb, variant, flavour, mode)};
}

void setWallpaper(const Paths& paths, const QString& wallArgument, bool noSmart) {
    const auto wall = canonicalPath(wallArgument);

    if (!isValidImage(wall)) {
        throw Error(u"\"%1\" is not a valid image"_s.arg(wall));
    }

    const auto config = loadUserConfig(paths);
    {
        const ThemeLock lock(paths.themeLock);

        // Everything that can fail on a bad image happens before any state changes.
        const auto cache = paths.wallpapersCache + u"/" + sha256File(wall);
        const auto thumb = thumbnailFor(wall, cache);

        auto scheme = Scheme::load(paths);
        if (scheme.name() == u"dynamic" && !noSmart) {
            const auto smart = smartOptions(wall, cache);
            scheme.setMode(smart.mode);
            scheme.setVariant(smart.variant);
        }
        scheme.refreshColoursFrom(thumb);

        writeFileAtomic(paths.wallpaperPath, wall.toUtf8());
        replaceSymlink(paths.wallpaperLink, wall);
        replaceSymlink(paths.wallpaperThumbnail, thumb);
        scheme.save();

        applyColours(lock, paths, config, scheme.colours(), scheme.mode());
    }

    runPostHook(config.postHook, wall);
}

void setRandomWallpaper(const Paths& paths, const RandomOptions& options) {
    auto walls = listWallpapers(options);

    if (walls.isEmpty()) {
        throw Error(u"No valid wallpapers found"_s);
    }

    if (const auto last = currentWallpaper(paths)) {
        const auto current = canonicalPath(*last);
        const auto remaining = [&] {
            QStringList others;
            for (const auto& wall : walls) {
                if (canonicalPath(wall) != current) {
                    others.append(wall);
                }
            }
            return others;
        }();
        // Only the current wallpaper available: keep it rather than fail.
        if (!remaining.isEmpty()) {
            walls = remaining;
        }
    }

    const auto index = QRandomGenerator::global()->bounded(static_cast<quint32>(walls.size()));
    setWallpaper(paths, walls.at(static_cast<qsizetype>(index)), options.noSmart);
}

} // namespace burl
