#include "theme.hpp"

#include "hypr.hpp"
#include "util.hpp"

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <qdir.h>
#include <qfileinfo.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qregularexpression.h>
#include <qstandardpaths.h>
#include <qtemporarydir.h>
#include <sys/file.h>
#include <unistd.h>

using Qt::StringLiterals::operator""_s;

namespace burl {

namespace {

QString lookup(const Colours& colours, const std::string& name) {
    for (const auto& [key, code] : colours) {
        if (key == name) {
            return QString::fromStdString(code);
        }
    }
    throw Error(u"missing colour: %1"_s.arg(QString::fromStdString(name)));
}

QString genConf(const Colours& colours) {
    QString conf;
    for (const auto& [name, colour] : colours) {
        conf += u"$%1 = %2\n"_s.arg(QString::fromStdString(name), QString::fromStdString(colour));
    }
    return conf;
}

QString genScss(const Colours& colours) {
    QString scss;
    for (const auto& [name, colour] : colours) {
        scss += u"$%1: #%2;\n"_s.arg(QString::fromStdString(name), QString::fromStdString(colour));
    }
    return scss;
}

QString readText(const QString& path) {
    return QString::fromUtf8(readFile(path));
}

QString genReplace(const Colours& colours, const QString& templatePath, bool hash = false) {
    auto text = readText(templatePath);
    for (const auto& [name, colour] : colours) {
        const auto code = QString::fromStdString(colour);
        text.replace(u"{{ $%1 }}"_s.arg(QString::fromStdString(name)), hash ? u"#" + code : code);
    }
    return text;
}

// A colour code padded with "f" to RRGGBBAA, as the user templates see it.
struct DynamicColour {
    QString hex[4];

    explicit DynamicColour(const QString& code) {
        const auto padded = code.leftJustified(8, u'f');
        for (int i = 0; i < 4; i++) {
            hex[i] = padded.mid(i * 2, 2);
        }
    }

    [[nodiscard]] static QString decimal(const QString& pair) { return QString::number(pair.toInt(nullptr, 16)); }

    [[nodiscard]] std::optional<QString> form(const QString& name) const {
        if (name == u"hex") {
            return hex[0] + hex[1] + hex[2];
        }
        if (name == u"hexalpha") {
            return hex[0] + hex[1] + hex[2] + hex[3];
        }
        if (name == u"rgb") {
            return u"rgb(%1,%2,%3)"_s.arg(decimal(hex[0]), decimal(hex[1]), decimal(hex[2]));
        }
        if (name == u"rgbalpha") {
            return u"rgba(%1,%2,%3,%4)"_s.arg(decimal(hex[0]), decimal(hex[1]), decimal(hex[2]), decimal(hex[3]));
        }
        return std::nullopt;
    }
};

QString genReplaceDynamic(const Colours& colours, const QString& templatePath, const QString& mode) {
    // Atomic {{ . }} pairs: no nested braces.
    static const QRegularExpression dotField(uR"(\{\{((?:(?!\{\{|\}\}).)*)\}\})"_s);
    static const QRegularExpression modeField(uR"(\{\{\s*mode\s*\}\})"_s);

    const auto content = readText(templatePath);

    QString filled;
    qsizetype last = 0;
    auto matches = dotField.globalMatch(content);
    while (matches.hasNext()) {
        const auto match = matches.next();
        filled += content.mid(last, match.capturedStart() - last);
        last = match.capturedEnd();

        const auto data = match.captured(1).trimmed().split(u'.');
        std::optional<QString> replacement;
        if (data.size() == 2) {
            for (const auto& [name, code] : colours) {
                if (name == data[0].toStdString()) {
                    replacement = DynamicColour(QString::fromStdString(code)).form(data[1]);
                    break;
                }
            }
        }
        filled += replacement.value_or(match.captured());
    }
    filled += content.mid(last);

    return filled.replace(modeField, mode);
}

QString c2s(const QString& colour, std::initializer_list<int> indexes) {
    QStringList parts;
    for (const auto index : indexes) {
        parts.append(QString::number(index));
    }
    return u"\x1b]%1;rgb:%2/%3/%4\x1b\\"_s.arg(parts.join(u';'), colour.mid(0, 2), colour.mid(2, 2), colour.mid(4, 2));
}

// 10 foreground, 11 background, 12 cursor, 17 selection; 4;N is palette entry
// N (0-7 normal, 8-15 bright, 16+ extended).
QString genSequences(const Colours& colours) {
    const auto get = [&](const std::string& name) { return lookup(colours, name); };

    auto sequences = c2s(get("onSurface"), {10}) + c2s(get("surface"), {11}) + c2s(get("secondary"), {12})
        + c2s(get("secondary"), {17});
    for (int i = 0; i < 16; i++) {
        sequences += c2s(get("term" + std::to_string(i)), {4, i});
    }
    return sequences + c2s(get("primary"), {4, 16}) + c2s(get("secondary"), {4, 17}) + c2s(get("tertiary"), {4, 18});
}

// These run while the theme lock is held, so a hung child must not hold it.
ProcessResult runBounded(const QString& program, const QStringList& arguments) {
    constexpr int timeoutMs = 30'000;
    auto result = runProcess(program, arguments, timeoutMs);
    if (result.timedOut) {
        logMessage(program.toStdString() + ": killed after " + std::to_string(timeoutMs / 1000) + "s timeout");
    }
    return result;
}

void write(const QString& path, const QString& content) {
    writeFileAtomic(path, content.toUtf8());
}

void applyTerms(const Paths& paths, const QString& sequences, const ThemeOptions& options) {
    const auto bytes = sequences.toUtf8();
    writeFileAtomic(paths.burlStateDir + u"/sequences.txt", bytes);
    if (!options.terminals) {
        return;
    }

    for (const auto& name : QDir(u"/dev/pts"_s).entryList(QDir::AllEntries | QDir::System | QDir::NoDotAndDotDot)) {
        bool numeric = false;
        name.toUInt(&numeric);
        if (!numeric) {
            continue;
        }
        // Non-blocking so a stuck terminal doesn't hang the whole apply.
        const auto fd = ::open(("/dev/pts/" + name.toStdString()).c_str(), O_WRONLY | O_NONBLOCK | O_NOCTTY);
        if (fd < 0) {
            continue;
        }
        const auto written = ::write(fd, bytes.constData(), static_cast<std::size_t>(bytes.size()));
        static_cast<void>(written);
        ::close(fd);
    }
}

QString luaString(const QString& value) {
    // Decimal byte escapes avoid JSON's Lua-incompatible Unicode escapes.
    QString result = u"\""_s;
    for (const auto byte : value.toUtf8()) {
        result += u"\\%1"_s.arg(static_cast<unsigned char>(byte), 3, 10, u'0');
    }
    return result + u"\""_s;
}

void applyHypr(const Paths& paths, const QString& conf, const ThemeOptions& options) {
    write(paths.configDir + u"/hypr/scheme/current.conf", conf);
    if (!options.commands || qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE").isEmpty()) {
        return;
    }

    const auto document = QJsonDocument::fromJson(hyprctl({u"-j"_s, u"monitors"_s, u"all"_s}, u"monitor query"_s).toUtf8());
    if (!document.isArray()) {
        throw Error(u"Hyprland monitor query did not return a list"_s);
    }

    QStringList disabled;
    for (const auto& entry : document.array()) {
        const auto monitor = entry.toObject();
        if (monitor.value(u"disabled"_s).toBool(false)) {
            const auto name = monitor.value(u"name"_s).toString();
            if (name.isEmpty()) {
                throw Error(u"Hyprland disabled monitor has no output name"_s);
            }
            disabled.append(name);
        }
    }

    QStringList errors;
    try {
        hyprctl({u"reload"_s}, u"reload"_s);
    } catch (const Error& error) {
        errors.append(QString::fromUtf8(error.what()));
    }
    for (const auto& name : disabled) {
        try {
            hyprctl({u"eval"_s, u"hl.monitor({ output = %1, disabled = true })"_s.arg(luaString(name))},
                    u"restore disabled output '%1'"_s.arg(name));
        } catch (const Error& error) {
            errors.append(QString::fromUtf8(error.what()));
        }
    }
    if (!errors.isEmpty()) {
        throw Error(errors.join(u"; "_s));
    }
}

void applyDiscord(const Paths& paths, const QString& scss, const ThemeOptions& options) {
    // Only the client-mod config dirs (Vencord, Equicord, ...) read this file.
    // Vanilla/Flatpak Discord never does, so there is nothing to generate for
    // unless one of these actually exists.
    QStringList installed;
    for (const auto* client : {"Equicord", "Vencord", "BetterDiscord", "equibop", "vesktop", "legcord"}) {
        if (QFileInfo(paths.configDir + u"/" + QString::fromLatin1(client)).isDir()) {
            installed.append(QString::fromLatin1(client));
        }
    }
    if (installed.isEmpty()) {
        logMessage("apply_discord(): no client-mod config dir found, skipping");
        return;
    }

    const auto sass = options.commands ? QStandardPaths::findExecutable(u"sass"_s) : QString();
    if (sass.isEmpty()) {
        logMessage("apply_discord(): found client-mod dir(s) " + installed.join(u", ").toStdString()
                   + " but no `sass` (dart-sass) binary on PATH, skipping theme generation");
        return;
    }

    QTemporaryDir directory;
    if (!directory.isValid()) {
        throw Error(directory.errorString());
    }
    write(directory.filePath(u"_colours.scss"_s), scss);
    const auto result = runBounded(sass, {u"-I"_s, directory.path(), paths.templates + u"/discord.scss"});
    if (result.exitCode != 0) {
        throw Error(u"Command '%1' returned non-zero exit status %2."_s.arg(sass).arg(result.exitCode));
    }

    for (const auto& client : installed) {
        writeFileAtomic(paths.configDir + u"/" + client + u"/themes/burl.theme.css", result.out);
    }
}

void applyPandora(const Paths& paths, const Colours& colours, const QString& mode) {
    auto text = genReplace(colours, paths.templates + u"/pandora.json", true);
    text.replace(u"{{ $mode }}"_s, mode);
    write(paths.dataDir + u"/PandoraLauncher/themes/burl.json", text);
}

void applySpicetify(const Paths& paths, const Colours& colours, const QString& mode, const ThemeOptions& options) {
    write(paths.configDir + u"/spicetify/Themes/burl/color.ini",
          genReplace(colours, paths.templates + u"/spicetify-" + mode + u".ini"));
    if (!options.commands) {
        return;
    }
    try {
        runBounded(u"spicetify"_s, {u"refresh"_s});
    } catch (const Error&) {
    }
}

void applySatty(const Paths& paths, const Colours& colours) {
    // Two files: config.toml carries the annotation palette, overrides.css the
    // toolbar chrome. Satty's own toolbars ship a hardcoded translucent-black
    // sheet that the shared GTK-4 stylesheet does not reach.
    write(paths.configDir + u"/satty/config.toml", genReplace(colours, paths.templates + u"/satty.toml", true));
    write(paths.configDir + u"/satty/overrides.css",
          genReplace(colours, paths.templates + u"/satty-overrides.css", true));
}

void signalReload(const QString& program, const ThemeOptions& options) {
    if (options.commands) {
        runBounded(u"killall"_s, {u"-USR2"_s, program});
    }
}

void applyBtop(const Paths& paths, const Colours& colours, const ThemeOptions& options) {
    write(paths.configDir + u"/btop/themes/burl.theme", genReplace(colours, paths.templates + u"/btop.theme", true));
    signalReload(u"btop"_s, options);
}

void applyNvtop(const Paths& paths, const Colours& colours) {
    write(paths.configDir + u"/nvtop/nvtop.colors", genReplace(colours, paths.templates + u"/nvtop.colors", true));
}

void applyHtop(const Paths& paths, const Colours& colours, const ThemeOptions& options) {
    write(paths.configDir + u"/htop/htoprc", genReplace(colours, paths.templates + u"/htop.theme", true));
    signalReload(u"htop"_s, options);
}

// GTK theming is not here: gtk.css and the gtk dconf keys are owned by the
// Guix Home configuration, and writing them at runtime fights its declarative
// entries.

void applyQt(const Paths& paths, const Colours& colours, const QString& mode) {
    const auto text = genReplace(colours, paths.templates + u"/qt" + mode + u".colors", true);
    write(paths.configDir + u"/qt5ct/colors/burl.colors", text);
    write(paths.configDir + u"/qt6ct/colors/burl.colors", text);

    auto capitalised = mode.toLower();
    if (!capitalised.isEmpty()) {
        capitalised[0] = capitalised[0].toUpper();
    }
    auto qtct = readText(paths.templates + u"/qtct.conf");
    qtct.replace(u"{{ $mode }}"_s, capitalised);

    for (const auto version : {5, 6}) {
        const auto dir = paths.configDir + u"/qt" + QString::number(version) + u"ct";
        auto conf = qtct;
        conf.replace(u"{{ $config }}"_s, dir);
        if (version == 5) {
            conf += uR"(
[Fonts]
fixed="Monospace,12,-1,5,50,0,0,0,0,0"
general="Sans Serif,12,-1,5,50,0,0,0,0,0"
)"_s;
        } else {
            conf += uR"(
[Fonts]
fixed="Monospace,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
general="Sans Serif,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
)"_s;
        }
        write(dir + u"/qt" + QString::number(version) + u"ct.conf", conf);
    }
}

void applyWarp(const Paths& paths, const Colours& colours, const QString& mode) {
    auto text = genReplace(colours, paths.templates + u"/warp.yaml", true);
    text.replace(u"{{ $warp_mode }}"_s, mode == u"dark" ? u"darker"_s : u"lighter"_s);
    write(paths.dataDir + u"/warp-terminal/themes/burl.yaml", text);
}

void applyCava(const Paths& paths, const Colours& colours, const ThemeOptions& options) {
    write(paths.configDir + u"/cava/config", genReplace(colours, paths.templates + u"/cava.conf", true));
    signalReload(u"cava"_s, options);
}

void applyUserTemplates(const Paths& paths, const Colours& colours, const QString& mode) {
    const QDir directory(paths.userTemplates);
    if (!directory.exists()) {
        return;
    }
    for (const auto& file : directory.entryInfoList(QDir::Files | QDir::Hidden | QDir::NoDotAndDotDot)) {
        write(paths.themeDir + u"/" + file.fileName(), genReplaceDynamic(colours, file.absoluteFilePath(), mode));
    }
}

} // namespace

ThemeLock::ThemeLock(const QString& path) {
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) {
        throw Error(path + ": cannot create directory");
    }
    m_fd = ::open(path.toLocal8Bit().constData(), O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (m_fd < 0) {
        throw Error(path + ": cannot open lock file");
    }
    while (::flock(m_fd, LOCK_EX) != 0) {
        if (errno != EINTR) {
            const auto message = path + ": cannot lock: " + QString::fromLocal8Bit(std::strerror(errno));
            ::close(m_fd);
            throw Error(message);
        }
    }
}

ThemeLock::~ThemeLock() {
    ::close(m_fd);
}

void applyColours(const ThemeLock&, const Paths& paths, const UserConfig& userConfig, const Colours& colours,
                  const QString& mode, const ThemeOptions& options) {
    const auto& config = userConfig.theme;
    const auto enabled = [&](const char* key) {
        const auto* value = config.find(key);
        return value ? value->truthy() : true;
    };

    if (enabled("enableTerm")) {
        const auto sequences = genSequences(colours);
        logged("apply_terms", [&] { applyTerms(paths, sequences, options); });
    }
    if (enabled("enableHypr")) {
        logged("apply_hypr", [&] { applyHypr(paths, genConf(colours), options); });
    }
    if (enabled("enableDiscord")) {
        logged("apply_discord", [&] { applyDiscord(paths, genScss(colours), options); });
    }
    if (enabled("enableSpicetify")) {
        logged("apply_spicetify", [&] { applySpicetify(paths, colours, mode, options); });
    }
    if (enabled("enablePandora")) {
        logged("apply_pandora", [&] { applyPandora(paths, colours, mode); });
    }
    if (enabled("enableSatty")) {
        logged("apply_satty", [&] { applySatty(paths, colours); });
    }
    if (enabled("enableBtop")) {
        logged("apply_btop", [&] { applyBtop(paths, colours, options); });
    }
    if (enabled("enableNvtop")) {
        logged("apply_nvtop", [&] { applyNvtop(paths, colours); });
    }
    if (enabled("enableHtop")) {
        logged("apply_htop", [&] { applyHtop(paths, colours, options); });
    }
    if (enabled("enableQt")) {
        logged("apply_qt", [&] { applyQt(paths, colours, mode); });
    }
    if (enabled("enableWarp")) {
        logged("apply_warp", [&] { applyWarp(paths, colours, mode); });
    }
    if (enabled("enableCava")) {
        logged("apply_cava", [&] { applyCava(paths, colours, options); });
    }
    logged("apply_user_templates", [&] { applyUserTemplates(paths, colours, mode); });
}

} // namespace burl
