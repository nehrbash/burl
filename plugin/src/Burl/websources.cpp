#include "websources.hpp"

#include <cstring>
#include <qbytearray.h>
#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qhash.h>
#include <qjsonarray.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qjsonvalue.h>
#include <qloggingcategory.h>
#include <qsqldatabase.h>
#include <qsqlerror.h>
#include <qsqlquery.h>
#include <qstandardpaths.h>
#include <qurl.h>
#include <quuid.h>
#include <qvariantmap.h>

Q_LOGGING_CATEGORY(lcWebSources, "burl.websources", QtInfoMsg)

using Qt::StringLiterals::operator""_s;

namespace burl {

namespace {

// Synthetic root + the six top-level Firefox/Zen folders. Edges into
// these are dropped so the graph isn't dominated by 4-5 huge fan-out
// hubs that mean nothing to the user.
constexpr int kRootBookmarkId = 1;
const QSet<QString>& syntheticTitles() {
    static const QSet<QString> s = { u"menu"_s, u"toolbar"_s, u"tags"_s, u"unfiled"_s, u"mobile"_s };
    return s;
}

// Copies places.sqlite (+ its WAL companion if present) into a temp
// location and returns the temp path. Reading the live places.sqlite
// directly fails because Zen / Firefox holds an exclusive write lock —
// even mode=ro can't acquire the necessary shared lock. The .sqlite-wal
// copy carries in-session writes so the snapshot is current.
QString snapshotPlaces(const QString& src) {
    if (src.isEmpty() || !QFileInfo::exists(src)) return {};

    const QString tmpRoot = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    QDir().mkpath(tmpRoot + u"/burl"_s);
    const QString dst = tmpRoot
        + u"/burl/places-"_s
        + QUuid::createUuid().toString(QUuid::Id128)
        + u".sqlite"_s;

    if (!QFile::copy(src, dst)) {
        qCWarning(lcWebSources) << "copy failed:" << src << "->" << dst;
        return {};
    }
    // SQLite's WAL must be next to the main file with the matching name.
    const QString srcWal = src + u"-wal"_s;
    if (QFileInfo::exists(srcWal)) {
        QFile::copy(srcWal, dst + u"-wal"_s);
    }
    return dst;
}

QSqlDatabase openSnapshot(const QString& path) {
    if (path.isEmpty() || !QFileInfo::exists(path)) {
        return QSqlDatabase();
    }
    const QString conn = QStringLiteral("burl-web-%1").arg(QUuid::createUuid().toString());
    auto db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), conn);
    db.setDatabaseName(path);
    db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY"));
    if (!db.open()) {
        qCWarning(lcWebSources) << "open failed:" << path << db.lastError().text();
        QSqlDatabase::removeDatabase(conn);
        return QSqlDatabase();
    }
    return db;
}

// Decodes a Mozilla "mozLz40\0" file (12-byte header + LZ4 block).
// The 8 magic bytes + 4 LE bytes (uncompressed size) precede a
// standard LZ4 block. Returns the decompressed bytes, or empty on
// any malformed input. Bounds-checked everywhere — sessionstore
// files can be truncated mid-write.
QByteArray decodeMozLz4(const QByteArray& blob) {
    static const char kMagic[] = "mozLz40\0";
    if (blob.size() < 12) return {};
    if (std::memcmp(blob.constData(), kMagic, 8) != 0) return {};
    const quint8* h = reinterpret_cast<const quint8*>(blob.constData()) + 8;
    const quint32 outLen = static_cast<quint32>(h[0])
                         | (static_cast<quint32>(h[1]) << 8)
                         | (static_cast<quint32>(h[2]) << 16)
                         | (static_cast<quint32>(h[3]) << 24);
    if (outLen == 0 || outLen > 64 * 1024 * 1024) return {};

    QByteArray out;
    out.resize(static_cast<int>(outLen));
    const quint8* in = reinterpret_cast<const quint8*>(blob.constData()) + 12;
    const qsizetype inLen = blob.size() - 12;
    qsizetype ip = 0;
    qsizetype op = 0;
    quint8* dst = reinterpret_cast<quint8*>(out.data());

    while (ip < inLen) {
        const quint8 token = in[ip++];
        // Literals
        qsizetype litLen = token >> 4;
        if (litLen == 15) {
            while (ip < inLen) {
                const quint8 b = in[ip++];
                litLen += b;
                if (b != 255) break;
            }
        }
        if (litLen > inLen - ip || litLen > static_cast<qsizetype>(outLen) - op) return {};
        std::memcpy(dst + op, in + ip, static_cast<size_t>(litLen));
        ip += litLen;
        op += litLen;
        if (ip >= inLen) break;

        // Match
        if (ip + 2 > inLen) return {};
        const quint16 offset = static_cast<quint16>(in[ip]) | (static_cast<quint16>(in[ip + 1]) << 8);
        ip += 2;
        if (offset == 0 || offset > op) return {};
        qsizetype matchLen = token & 0x0F;
        if (matchLen == 15) {
            while (ip < inLen) {
                const quint8 b = in[ip++];
                matchLen += b;
                if (b != 255) break;
            }
        }
        matchLen += 4;
        if (matchLen > static_cast<qsizetype>(outLen) - op) return {};
        // Byte-by-byte copy (offset may be < matchLen — overlapping
        // copy is part of LZ4's spec).
        for (qsizetype k = 0; k < matchLen; ++k) dst[op + k] = dst[op + k - offset];
        op += matchLen;
    }
    if (op != static_cast<qsizetype>(outLen)) return {};
    return out;
}

void closeAndRemove(QSqlDatabase& db) {
    const QString name = db.connectionName();
    db.close();
    db = QSqlDatabase();
    QSqlDatabase::removeDatabase(name);
}

} // namespace

WebSources::WebSources(QObject* parent) : QObject(parent) {
    m_debounce.setSingleShot(true);
    // Browser writes the journal a lot during a session — debounce
    // longer than EmacsSources so we don't thrash on every history hit.
    m_debounce.setInterval(2000);
    QObject::connect(&m_debounce, &QTimer::timeout, this, &WebSources::reload);

    QObject::connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this]() {
        rewatch();
        scheduleReload();
    });

    m_placesDb = resolveDefaultPlacesDb();
    rewatch();
    QTimer::singleShot(0, this, &WebSources::reload);
}

void WebSources::setPlacesDb(const QString& path) {
    if (m_placesDb == path) return;
    m_placesDb = path;
    emit placesDbChanged();
    rewatch();
    reload();
}

void WebSources::setHistoryLimit(int n) {
    if (m_historyLimit == n) return;
    m_historyLimit = n;
    emit historyLimitChanged();
    reload();
}

void WebSources::setBookmarkLimit(int n) {
    if (m_bookmarkLimit == n) return;
    m_bookmarkLimit = n;
    emit bookmarkLimitChanged();
    reload();
}

QString WebSources::sessionstoreFor(const QString& placesDb) const {
    if (placesDb.isEmpty()) return {};
    const QString profileDir = QFileInfo(placesDb).absolutePath();
    const QString candidate = profileDir + u"/sessionstore-backups/recovery.jsonlz4"_s;
    return QFileInfo::exists(candidate) ? candidate : QString();
}

QString WebSources::resolveDefaultPlacesDb() const {
    // Prefer Zen Browser flatpak install, falling back to firefox.
    const QString home = QDir::homePath();
    const QStringList roots = {
        home + u"/.var/app/app.zen_browser.zen/.zen"_s,
        home + u"/.zen"_s,
        home + u"/.mozilla/firefox"_s,
    };
    for (const auto& root : roots) {
        QDir dir(root);
        if (!dir.exists()) continue;
        // Profile dirs look like "<random>.<name>" — pick the first that
        // contains a places.sqlite. profiles.ini parsing is overkill.
        const auto entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Time);
        for (const auto& e : entries) {
            const QString candidate = dir.absoluteFilePath(e) + u"/places.sqlite"_s;
            if (QFileInfo::exists(candidate)) return candidate;
        }
    }
    return {};
}

void WebSources::rewatch() {
    if (!m_watcher.files().isEmpty()) {
        m_watcher.removePaths(m_watcher.files());
    }
    if (!m_placesDb.isEmpty() && QFileInfo::exists(m_placesDb)) {
        m_watcher.addPath(m_placesDb);
        // WAL captures recent writes; watching it picks up the browser's
        // in-session updates as well as full checkpoints.
        const QString wal = m_placesDb + QStringLiteral("-wal");
        if (QFileInfo::exists(wal)) m_watcher.addPath(wal);
    }
    const QString sess = sessionstoreFor(m_placesDb);
    if (!sess.isEmpty()) m_watcher.addPath(sess);
}

void WebSources::scheduleReload() { m_debounce.start(); }

void WebSources::reload() {
    if (m_placesDb.isEmpty()) {
        qCInfo(lcWebSources) << "no places.sqlite — skipping load";
        return;
    }

    // Tabs are independent of places.sqlite (separate file), so load
    // them first — the sqlite snapshot can still fail if the browser
    // is mid-write, but we shouldn't lose tab data over it.
    reloadTabs();

    const QString snapshot = snapshotPlaces(m_placesDb);
    if (snapshot.isEmpty()) return;
    QSqlDatabase db = openSnapshot(snapshot);
    if (!db.isValid()) {
        QFile::remove(snapshot);
        QFile::remove(snapshot + u"-wal"_s);
        return;
    }

    QVariantList bookmarks;
    QVariantList links;
    QSet<int> emittedIds;
    {
        // Bookmarks: type=1 (item) or type=2 (folder). Title can be NULL
        // for separators (type=3); we skip those. fk is the moz_places.id
        // for type=1; folders have fk=NULL and a title.
        QSqlQuery q(db);
        const QString sql = QStringLiteral(
            "SELECT b.id, b.type, b.parent, COALESCE(b.title, ''), p.url "
            "FROM moz_bookmarks b LEFT JOIN moz_places p ON p.id = b.fk "
            "WHERE b.type IN (1, 2) "
            "ORDER BY b.parent, b.position "
            "LIMIT %1").arg(m_bookmarkLimit * 4);  // headroom for folders + items
        if (!q.exec(sql)) {
            qCWarning(lcWebSources) << "bookmark query failed:" << q.lastError().text();
        } else {
            int kept = 0;
            while (q.next() && kept < m_bookmarkLimit) {
                const int id = q.value(0).toInt();
                const int type = q.value(1).toInt();
                const int parent = q.value(2).toInt();
                const QString title = q.value(3).toString();
                const QString url = q.value(4).toString();

                if (id == kRootBookmarkId) continue;
                // Skip the 5 synthetic top-level folders themselves. We
                // still emit their *children* but with no parent edge.
                if (parent == kRootBookmarkId && syntheticTitles().contains(title)) continue;
                if (type == 1 && url.isEmpty()) continue;

                QVariantMap entry;
                entry[QStringLiteral("id")] = id;
                entry[QStringLiteral("parentId")] = parent;
                entry[QStringLiteral("title")] = title.isEmpty() ? url : title;
                entry[QStringLiteral("url")] = url;
                entry[QStringLiteral("isFolder")] = (type == 2);
                bookmarks.append(entry);
                emittedIds.insert(id);
                ++kept;
            }
        }

        // Build edges from emitted nodes whose parent is also emitted.
        // Root + top-level synthetic folders are NOT emitted, so children
        // of those naturally end up parent-less in the graph.
        for (const auto& v : bookmarks) {
            const QVariantMap m = v.toMap();
            const int id = m.value(QStringLiteral("id")).toInt();
            const int parent = m.value(QStringLiteral("parentId")).toInt();
            if (parent <= 0 || !emittedIds.contains(parent)) continue;
            QVariantMap edge;
            edge[QStringLiteral("source")] = id;
            edge[QStringLiteral("dest")] = parent;
            links.append(edge);
        }
    }

    QVariantList history;
    {
        // moz_places.hidden = 1 for places loaded as resources / iframes;
        // they're not user-navigations. frecency-sorted picks pages
        // weighted by both recency and visit count, which is what users
        // actually want from "history" rather than raw last-visit.
        QSqlQuery q(db);
        q.prepare(QStringLiteral(
            "SELECT url, COALESCE(title, ''), visit_count "
            "FROM moz_places "
            "WHERE hidden = 0 AND visit_count > 0 "
            "ORDER BY frecency DESC, last_visit_date DESC "
            "LIMIT :lim"));
        q.bindValue(QStringLiteral(":lim"), m_historyLimit);
        if (!q.exec()) {
            qCWarning(lcWebSources) << "history query failed:" << q.lastError().text();
        } else {
            while (q.next()) {
                QVariantMap entry;
                const QString url = q.value(0).toString();
                const QString title = q.value(1).toString();
                entry[QStringLiteral("url")] = url;
                entry[QStringLiteral("title")] = title.isEmpty() ? url : title;
                entry[QStringLiteral("visitCount")] = q.value(2).toInt();
                history.append(entry);
            }
        }
    }

    closeAndRemove(db);
    // SQLite may have created a -shm alongside our temp .sqlite while
    // it opened the WAL — clean all three.
    QFile::remove(snapshot);
    QFile::remove(snapshot + u"-wal"_s);
    QFile::remove(snapshot + u"-shm"_s);

    // Build hub-and-spoke edges per host. For each domain with more
    // than one entry, the FIRST entry (frecency-sorted at the top of
    // 'history') becomes the hub; every other entry on that host
    // links to it. Cheap O(n) — n is bounded by m_historyLimit.
    QVariantList historyLinks;
    QHash<QString, QString> hubByHost;  // host -> hub URL
    for (const auto& v : history) {
        const QVariantMap m = v.toMap();
        const QString url = m.value(u"url"_s).toString();
        const QString host = QUrl(url).host();
        if (host.isEmpty()) continue;
        const auto it = hubByHost.constFind(host);
        if (it == hubByHost.constEnd()) {
            hubByHost.insert(host, url);
            continue;
        }
        QVariantMap edge;
        edge[u"source"_s] = url;
        edge[u"dest"_s] = it.value();
        historyLinks.append(edge);
    }

    m_bookmarks = std::move(bookmarks);
    m_bookmarkLinks = std::move(links);
    m_history = std::move(history);
    m_historyLinks = std::move(historyLinks);
    emit bookmarksChanged();
    emit historyChanged();
}

void WebSources::reloadTabs() {
    const QString path = sessionstoreFor(m_placesDb);
    if (path.isEmpty()) {
        if (!m_tabs.isEmpty() || !m_tabLinks.isEmpty()) {
            m_tabs.clear();
            m_tabLinks.clear();
            emit tabsChanged();
        }
        return;
    }
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        qCWarning(lcWebSources) << "tabs open failed:" << path << f.errorString();
        return;
    }
    const QByteArray raw = f.readAll();
    f.close();
    const QByteArray json = decodeMozLz4(raw);
    if (json.isEmpty()) {
        qCWarning(lcWebSources) << "tabs decompress failed:" << path;
        return;
    }
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError) {
        qCWarning(lcWebSources) << "tabs parse failed:" << err.errorString();
        return;
    }

    QVariantList tabs;
    QVariantList links;
    QHash<QString, QString> hubByHost;
    const QJsonArray windows = doc.object().value(u"windows"_s).toArray();
    for (const auto& w : windows) {
        const QJsonArray wtabs = w.toObject().value(u"tabs"_s).toArray();
        int tabPos = 0;
        for (const auto& t : wtabs) {
            ++tabPos;
            const QJsonObject tab = t.toObject();
            const QJsonArray entries = tab.value(u"entries"_s).toArray();
            if (entries.isEmpty()) continue;
            // Mozilla's "index" is 1-based and points at the currently
            // active entry in the tab's history. Clamp defensively.
            int idx = tab.value(u"index"_s).toInt(static_cast<int>(entries.size()));
            if (idx < 1) idx = 1;
            if (idx > entries.size()) idx = static_cast<int>(entries.size());
            const QJsonObject entry = entries.at(idx - 1).toObject();
            const QString url = entry.value(u"url"_s).toString();
            if (url.isEmpty() || url.startsWith(u"about:"_s)) continue;
            const QString title = entry.value(u"title"_s).toString();

            QVariantMap m;
            m[u"url"_s] = url;
            m[u"title"_s] = title.isEmpty() ? url : title;
            // 1-based position within the parent window — useful for
            // sending Ctrl+<n> to switch to the tab after focusing.
            m[u"tabIndex"_s] = tabPos;
            tabs.append(m);

            const QString host = QUrl(url).host();
            if (host.isEmpty()) continue;
            const auto it = hubByHost.constFind(host);
            if (it == hubByHost.constEnd()) {
                hubByHost.insert(host, url);
            } else {
                QVariantMap edge;
                edge[u"source"_s] = url;
                edge[u"dest"_s] = it.value();
                links.append(edge);
            }
        }
    }

    m_tabs = std::move(tabs);
    m_tabLinks = std::move(links);
    emit tabsChanged();
}

} // namespace burl
