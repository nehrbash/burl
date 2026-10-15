#include "material.hpp"

#include "util.hpp"

#include <qdir.h>
#include <qfileinfo.h>

using Qt::StringLiterals::operator""_s;

namespace burl {

namespace {

// Seed colour of `image`, cached beside the generated schemes.
std::uint32_t scoreForImage(const QString& image, const QString& cacheBase) {
    const auto cache = cacheBase + u"/score.json";

    try {
        bool ok = false;
        const auto cached = QString::fromUtf8(readFile(cache)).trimmed().toLongLong(&ok);
        if (ok) {
            return static_cast<std::uint32_t>(cached & 0xFFFFFFFF);
        }
    } catch (const Error&) {
    }

    const auto score = colour::scoreImage(image.toStdString());
    writeFileAtomic(cache, QByteArray::number(score));
    return score;
}

} // namespace

Colours coloursForImage(const Paths& paths, const QString& image, const QString& variant, const QString& flavour,
                        const QString& mode) {
    const auto cacheBase = paths.schemeCache + u"/" + sha256File(image);
    const auto cache = cacheBase + u"/" + variant + u"/" + flavour + u"/" + mode + u".json";

    try {
        const auto json = parseJson(readFile(cache).toStdString());
        if (json.isObject()) {
            Colours colours;
            for (const auto& [name, code] : json.members()) {
                if (!code.isString()) {
                    throw JsonError("invalid colour");
                }
                colours.emplace_back(name, code.asString());
            }
            return colours;
        }
    } catch (const Error&) {
    } catch (const JsonError&) {
    }

    const auto seed = scoreForImage(image, cacheBase);
    const auto colours = colour::generate({variant.toStdString(), flavour.toStdString(), mode.toStdString()}, seed);
    writeFileAtomic(cache, QByteArray::fromStdString(dumpJson(coloursToJson(colours))));
    return colours;
}

} // namespace burl
