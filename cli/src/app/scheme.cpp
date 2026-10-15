#include "scheme.hpp"

#include "material.hpp"
#include "notify.hpp"
#include "util.hpp"

#include <qdir.h>
#include <qfileinfo.h>
#include <qrandom.h>

using Qt::StringLiterals::operator""_s;

namespace burl {

const QStringList schemeVariants = {
    u"tonalspot"_s, u"vibrant"_s, u"expressive"_s, u"fidelity"_s, u"fruitsalad"_s,
    u"monochrome"_s, u"neutral"_s, u"rainbow"_s, u"content"_s,
};

namespace {

QStringList listEntries(const QString& dir, QDir::Filters filters) {
    return QDir(dir).entryList(filters | QDir::Hidden | QDir::NoDotAndDotDot, QDir::Name);
}

QStringList requireEntries(const QStringList& entries, const QString& what) {
    if (entries.isEmpty()) {
        throw Error(u"No %1 found"_s.arg(what));
    }
    return entries;
}

const QString& randomChoice(const QStringList& list) {
    return list.at(static_cast<qsizetype>(QRandomGenerator::global()->bounded(static_cast<quint32>(list.size()))));
}

} // namespace

JsonValue coloursToJson(const Colours& colours) {
    auto result = JsonValue::object();
    for (const auto& [name, code] : colours) {
        result.set(name, JsonValue::string(code));
    }
    return result;
}

QStringList schemeNames(const Paths& paths) {
    auto names = listEntries(paths.schemeData, QDir::Dirs);
    names.append(u"dynamic"_s);
    return names;
}

QStringList schemeFlavours(const Paths& paths, const QString& name) {
    if (name == u"dynamic") {
        return {u"default"_s, u"hard"_s};
    }
    return listEntries(paths.schemeData + u"/" + name, QDir::Dirs);
}

QStringList schemeModes(const Paths& paths, const QString& name, const QString& flavour) {
    if (name == u"dynamic") {
        return {u"light"_s, u"dark"_s};
    }
    QStringList modes;
    for (const auto& file : listEntries(paths.schemeData + u"/" + name + u"/" + flavour, QDir::Files)) {
        modes.append(pathStem(file));
    }
    return modes;
}

Colours readColoursFromFile(const QString& path) {
    const auto text = QString::fromUtf8(readFile(path));
    Colours colours;
    for (const auto& line : text.split(u'\n')) {
        auto trimmed = line;
        if (trimmed.endsWith(u'\r')) {
            trimmed.chop(1);
        }
        if (trimmed.isEmpty()) {
            continue;
        }
        const auto parts = trimmed.split(u' ');
        if (parts.size() != 2) {
            throw Error(u"%1: invalid colour line \"%2\""_s.arg(path, trimmed));
        }
        colours.emplace_back(parts[0].trimmed().toStdString(), parts[1].trimmed().toStdString());
    }
    return colours;
}

Scheme::Scheme(const Paths& paths, QString name, QString flavour, QString mode, QString variant, Colours colours)
    : m_paths(paths)
    , m_name(std::move(name))
    , m_flavour(std::move(flavour))
    , m_mode(std::move(mode))
    , m_variant(std::move(variant))
    , m_colours(std::move(colours)) {}

Scheme Scheme::load(const Paths& paths) {
    try {
        const auto json = parseJson(readFile(paths.scheme).toStdString());
        const auto field = [&](const char* key) {
            const auto* value = json.find(key);
            if (!value || !value->isString()) {
                throw JsonError(std::string("missing ") + key);
            }
            return QString::fromStdString(value->asString());
        };

        Colours colours;
        const auto* stored = json.find("colours");
        if (!stored || !stored->isObject()) {
            throw JsonError("missing colours");
        }
        for (const auto& [key, value] : stored->members()) {
            if (!value.isString()) {
                throw JsonError("invalid colour");
            }
            colours.emplace_back(key, value.asString());
        }
        return {paths, field("name"), field("flavour"), field("mode"), field("variant"), std::move(colours)};
    } catch (const FileNotFound&) {
    } catch (const JsonError&) {
    }

    Scheme scheme(paths, u"nocturne"_s, u"default"_s, u"dark"_s, u"tonalspot"_s, {});
    scheme.m_colours = readColoursFromFile(scheme.coloursPath());
    return scheme;
}

void Scheme::setMode(const QString& mode) {
    if (mode == m_mode) {
        return;
    }
    const auto modes = schemeModes(m_paths, m_name, m_flavour);
    if (!modes.contains(mode)) {
        if (m_notify) {
            notifyCritical(u"Unable to set scheme mode"_s,
                           u"Scheme \"%1 %2\" does not have a %3 mode."_s.arg(m_name, m_flavour, mode));
        }
        throw Error(u"Invalid scheme mode: \"%1\". Valid modes: %2"_s.arg(mode, modes.join(u", ")));
    }
    m_mode = mode;
}

void Scheme::setVariant(const QString& variant) {
    if (variant == m_variant) {
        return;
    }
    m_variant = variant;
}

void Scheme::select(const QString& name, const QString& flavour, const QString& mode, const QString& variant) {
    Scheme candidate(m_paths, name.isEmpty() ? m_name : name, flavour.isEmpty() ? m_flavour : flavour,
                     mode.isEmpty() ? m_mode : mode, variant.isEmpty() ? m_variant : variant, m_colours);
    candidate.m_notify = m_notify;

    if (!schemeNames(m_paths).contains(candidate.m_name)) {
        throw Error(u"Invalid scheme: %1"_s.arg(candidate.m_name));
    }
    if (!flavour.isEmpty() && !schemeFlavours(m_paths, candidate.m_name).contains(flavour)) {
        throw Error(u"Invalid flavour for %1: %2"_s.arg(candidate.m_name, flavour));
    }
    candidate.checkFlavour();
    if (!mode.isEmpty() && !schemeModes(m_paths, candidate.m_name, candidate.m_flavour).contains(mode)) {
        throw Error(u"Scheme %1 %2 has no %3 appearance"_s.arg(candidate.m_name, candidate.m_flavour, mode));
    }
    candidate.checkMode();
    if (!schemeVariants.contains(candidate.m_variant)) {
        throw Error(u"Invalid variant: %1"_s.arg(candidate.m_variant));
    }
    candidate.refreshColours();
    candidate.save();

    m_name = candidate.m_name;
    m_flavour = candidate.m_flavour;
    m_mode = candidate.m_mode;
    m_variant = candidate.m_variant;
    m_colours = std::move(candidate.m_colours);
}

void Scheme::setRandom() {
    m_name = randomChoice(requireEntries(schemeNames(m_paths), u"schemes"_s));
    m_flavour = randomChoice(requireEntries(schemeFlavours(m_paths, m_name), u"flavours"_s));
    m_mode = randomChoice(requireEntries(schemeModes(m_paths, m_name, m_flavour), u"modes"_s));
    updateColours();
}

void Scheme::updateColours() {
    refreshColours();
    save();
}

void Scheme::refreshColours() {
    refreshColoursFrom(m_paths.wallpaperThumbnail);
}

void Scheme::refreshColoursFrom(const QString& image) {
    if (m_name != u"dynamic") {
        m_colours = readColoursFromFile(coloursPath());
        return;
    }

    try {
        m_colours = coloursForImage(m_paths, image, m_variant, m_flavour, m_mode);
    } catch (const FileNotFound&) {
        const auto message = u"No wallpaper set. Please set a wallpaper via `burl wallpaper` before setting a dynamic scheme."_s;
        if (m_notify) {
            notifyCritical(u"Unable to set dynamic scheme"_s, message);
        }
        throw Error(message);
    }
}

void Scheme::save() const {
    auto json = JsonValue::object();
    json.set("name", JsonValue::string(m_name.toStdString()));
    json.set("flavour", JsonValue::string(m_flavour.toStdString()));
    json.set("mode", JsonValue::string(m_mode.toStdString()));
    json.set("variant", JsonValue::string(m_variant.toStdString()));
    json.set("colours", coloursToJson(m_colours));
    const auto text = dumpJson(json);
    writeFileAtomic(m_paths.scheme, QByteArray::fromStdString(text));
}

QString Scheme::coloursPath() const {
    return m_paths.schemeData + u"/" + m_name + u"/" + m_flavour + u"/" + m_mode + u".txt";
}

QString Scheme::summary() const {
    QStringList lines;
    for (const auto& [name, code] : m_colours) {
        const auto hex = QString::fromStdString(code);
        bool ok = true;
        const auto channel = [&](qsizetype start) {
            bool part = false;
            const auto value = hex.mid(start, 2).toInt(&part, 16);
            ok = ok && part;
            return value;
        };
        const auto r = channel(0);
        const auto g = channel(2);
        const auto b = channel(4);
        if (!ok) {
            throw Error(u"invalid colour %1: %2"_s.arg(QString::fromStdString(name), hex));
        }
        lines.append(u"%1: \x1b[38;2;%2;%3;%4m%5\x1b[0m"_s.arg(QString::fromStdString(name)).arg(r).arg(g).arg(b).arg(hex));
    }
    return u"Current scheme:\n    Name: %1\n    Flavour: %2\n    Mode: %3\n    Variant: %4\n    Colours:\n        "_s.arg(
               m_name, m_flavour, m_mode, m_variant)
        + lines.join(u"\n        ");
}

void Scheme::checkFlavour() {
    const auto flavours = requireEntries(schemeFlavours(m_paths, m_name), u"flavours"_s);
    if (!flavours.contains(m_flavour)) {
        m_flavour = flavours.first();
    }
}

void Scheme::checkMode() {
    const auto modes = requireEntries(schemeModes(m_paths, m_name, m_flavour), u"modes"_s);
    if (!modes.contains(m_mode)) {
        m_mode = modes.first();
    }
}

} // namespace burl
