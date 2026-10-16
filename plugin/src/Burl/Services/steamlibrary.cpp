#include "steamlibrary.hpp"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSet>
#include <QUrl>
#include <QtConcurrentRun>
#include <algorithm>

namespace burl::services {
namespace steam {
namespace {

class VdfReader {
public:
    explicit VdfReader(const QByteArray& data) : text(QString::fromUtf8(data)) {}

    QVariantMap read(int depth = 0, bool nested = false) {
        QVariantMap result;
        if (depth > 16) { valid = false; return {}; }
        while (valid) {
            skip();
            if (pos == text.size()) { valid = !nested; break; }
            if (text[pos] == '}') {
                ++pos;
                if (!nested) valid = false;
                return result;
            }
            const auto key = token();
            skip();
            if (!valid || pos == text.size()) { valid = false; break; }
            if (text[pos] == '{') {
                ++pos;
                result.insert(key.toLower(), read(depth + 1, true));
            } else {
                result.insert(key.toLower(), token());
            }
        }
        return result;
    }
    bool valid = true;

private:
    void skip() {
        while (pos < text.size()) {
            if (text[pos].isSpace()) { ++pos; continue; }
            if (text.mid(pos, 2) == "//") {
                while (pos < text.size() && text[pos] != '\n') ++pos;
                continue;
            }
            break;
        }
    }
    QString token() {
        skip();
        QString value;
        if (pos == text.size() || text[pos] == '{' || text[pos] == '}') {
            valid = false;
            return value;
        }
        if (text[pos] != '"') {
            while (pos < text.size() && !text[pos].isSpace() && text[pos] != '{' && text[pos] != '}')
                value += text[pos++];
            return value;
        }
        ++pos;
        while (pos < text.size()) {
            const auto ch = text[pos++];
            if (ch == '"') return value;
            if (ch == '\\' && pos < text.size() && (text[pos] == '\\' || text[pos] == '"'))
                value += text[pos++];
            else
                value += ch;
        }
        valid = false;
        return value;
    }
    QString text;
    qsizetype pos = 0;
};

bool runtime(const QVariantMap& state) {
    const auto name = state.value("name").toString();
    const auto dir = state.value("installdir").toString();
    static const QRegularExpression proton("^Proton(?: -)? (?:Experimental|Hotfix|[0-9]+(?:[.][0-9]+)*(?:.*))$",
        QRegularExpression::CaseInsensitiveOption);
    // App manifests have no dependable game/tool type; restrict exclusions to Steam support packages.
    return dir.startsWith("SteamLinuxRuntime", Qt::CaseInsensitive)
        || name.startsWith("Steam Linux Runtime ", Qt::CaseInsensitive)
        || dir.compare("Steamworks Shared", Qt::CaseInsensitive) == 0
        || name.compare("Steamworks Common Redistributables", Qt::CaseInsensitive) == 0
        || proton.match(name).hasMatch() || proton.match(dir).hasMatch();
}

}

QVariantMap parseVdf(const QByteArray& data) {
    VdfReader reader(data);
    auto result = reader.read();
    return reader.valid ? result : QVariantMap{};
}

ScanResult scan(const QStringList& roots, const QString& home, const QString& sandboxHome) {
    ScanResult result;
    QSet<QString> watched, libraries, ids;
    QStringList queue;
    qint64 bytesRemaining = 16 * 1024 * 1024;
    int manifestsRemaining = 4096;
    const auto watch = [&](QString path) {
        while (!QFileInfo::exists(path)) {
            const auto parent = QFileInfo(path).absolutePath();
            if (parent == path) return;
            path = parent;
        }
        watched.insert(path);
    };
    const auto addLibrary = [&](const QString& path) {
        if (path.isEmpty() || !QDir::isAbsolutePath(path) || queue.size() >= 64) return;
        const auto canonical = QFileInfo(path).canonicalFilePath();
        const auto normalized = canonical.isEmpty() ? QDir::cleanPath(path) : canonical;
        if (libraries.contains(normalized)) return;
        libraries.insert(normalized);
        queue.append(normalized);
    };
    const auto read = [&](const QString& path) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly) || file.size() > 1024 * 1024 || file.size() > bytesRemaining)
            return QVariantMap{};
        const auto data = file.read(1024 * 1024 + 1);
        bytesRemaining -= data.size();
        return data.size() <= 1024 * 1024 ? parseVdf(data) : QVariantMap{};
    };
    const auto cover = [&](const QString& id) {
        for (const auto& root : roots) {
            const auto cache = root + "/appcache/librarycache";
            const auto legacy = cache + "/" + id + "_library_600x900.jpg";
            if (QFileInfo(legacy).isFile()) { watch(legacy); return QUrl::fromLocalFile(legacy).toString(); }
            const auto appCache = cache + "/" + id;
            watch(appCache);
            QStringList dirs{appCache};
            QDirIterator hashes(appCache, QDir::Dirs | QDir::NoDotAndDotDot);
            while (hashes.hasNext() && dirs.size() <= 32) dirs.append(hashes.next());
            for (const auto& dir : dirs) {
                watch(dir);
                const auto path = dir + "/library_600x900.jpg";
                if (QFileInfo(path).isFile()) { watch(path); return QUrl::fromLocalFile(path).toString(); }
            }
        }
        return QString{};
    };
    for (const auto& root : roots) addLibrary(root);
    for (qsizetype i = 0; i < queue.size(); ++i) {
        const auto library = queue[i];
        const auto steamapps = library + "/steamapps";
        watch(steamapps);
        watch(steamapps + "/common");
        const auto foldersPath = steamapps + "/libraryfolders.vdf";
        watch(foldersPath);
        const auto folders = read(foldersPath).value("libraryfolders").toMap();
        for (auto it = folders.cbegin(); it != folders.cend(); ++it) {
            bool numbered;
            it.key().toUInt(&numbered);
            if (!numbered) continue;
            auto path = it.value().metaType().id() == QMetaType::QVariantMap
                ? it.value().toMap().value("path").toString() : it.value().toString();
            // Steam records the sandbox's logical home, while Burl runs outside it.
            if (library.startsWith(sandboxHome + "/") && path.startsWith(home + "/")) {
                const auto mapped = sandboxHome + path.mid(home.size());
                if (QFileInfo::exists(mapped)) path = mapped;
            }
            addLibrary(path);
        }
        const QDir dir(steamapps);
        QDirIterator files(steamapps, {"appmanifest_*.acf"}, QDir::Files);
        while (files.hasNext() && manifestsRemaining > 0 && bytesRemaining > 0) {
            --manifestsRemaining;
            const auto path = files.next();
            const auto filename = files.fileName();
            watch(path);
            const auto state = read(path).value("appstate").toMap();
            const auto id = state.value("appid").toString();
            static const QRegularExpression numeric("^[1-9][0-9]{0,9}$");
            bool validId;
            const auto appId = id.toULongLong(&validId);
            if (!validId || appId > 0xffffffffULL || !numeric.match(id).hasMatch()
                || filename != "appmanifest_" + id + ".acf" || ids.contains(id)) continue;
            const auto name = state.value("name").toString().trimmed();
            const auto install = state.value("installdir").toString();
            if (name.isEmpty() || install.isEmpty() || install == "." || install == ".."
                || install.contains('/') || install.contains('\\') || runtime(state)) continue;
            const auto installDir = dir.filePath("common/" + install);
            if (!QFileInfo(installDir).isDir()) continue;
            ids.insert(id);
            QVariantMap game{{"appId", id}, {"name", name}, {"installDir", installDir}};
            const auto image = cover(id);
            if (!image.isEmpty()) game.insert("imageUrl", image);
            result.games.append(game);
        }
    }
    std::sort(result.games.begin(), result.games.end(), [](const QVariant& a, const QVariant& b) {
        const auto am = a.toMap(), bm = b.toMap();
        const auto order = QString::compare(am.value("name").toString(), bm.value("name").toString(), Qt::CaseInsensitive);
        return order ? order < 0 : am.value("appId").toString() < bm.value("appId").toString();
    });
    result.watchPaths = watched.values();
    return result;
}
}

SteamLibrary::SteamLibrary(QObject* parent) : QObject(parent) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(250);
    connect(&m_files, &QFileSystemWatcher::fileChanged, &m_debounce, qOverload<>(&QTimer::start));
    connect(&m_files, &QFileSystemWatcher::directoryChanged, &m_debounce, qOverload<>(&QTimer::start));
    connect(&m_debounce, &QTimer::timeout, this, &SteamLibrary::refresh);
    connect(&m_scan, &QFutureWatcher<steam::ScanResult>::finished, this, [this] {
        const auto result = m_scan.result();
        const auto oldPaths = m_files.files() + m_files.directories();
        if (!oldPaths.isEmpty()) m_files.removePaths(oldPaths);
        if (!result.watchPaths.isEmpty()) m_files.addPaths(result.watchPaths);
        if (m_games != result.games) {
            m_games = result.games;
            emit gamesChanged();
        }
        if (m_pending) { m_pending = false; m_debounce.start(); }
    });
    refresh();
}

void SteamLibrary::refresh() {
    if (m_scan.isRunning()) { m_pending = true; return; }
    const auto home = QDir::homePath();
    const auto sandbox = qEnvironmentVariable("GUIX_SANDBOX_HOME", home + "/.local/share/guix-sandbox-home");
    const auto dataHome = qEnvironmentVariable("XDG_DATA_HOME", home + "/.local/share");
    const QStringList roots{dataHome + "/Steam", home + "/.steam/steam", home + "/.steam/root",
        home + "/.var/app/com.valvesoftware.Steam/.local/share/Steam",
        sandbox + "/.local/share/Steam", sandbox + "/.steam/steam", sandbox + "/.steam/root"};
    m_scan.setFuture(QtConcurrent::run([roots, home, sandbox] { return steam::scan(roots, home, sandbox); }));
}
}
