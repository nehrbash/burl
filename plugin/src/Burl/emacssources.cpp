#include "emacssources.hpp"

#include <qfileinfo.h>
#include <qloggingcategory.h>
#include <qsqldatabase.h>
#include <qsqlerror.h>
#include <qsqlquery.h>
#include <quuid.h>
#include <qvariantmap.h>

Q_LOGGING_CATEGORY(lcEmacsSources, "burl.emacssources", QtInfoMsg)

namespace burl {

namespace {

// Org-roam stores text values as printed elisp (titles wrapped in literal
// double quotes). Strip a single pair of surrounding quotes if present.
QString unquote(const QString& s) {
    if (s.size() >= 2 && s.startsWith(QLatin1Char('"')) && s.endsWith(QLatin1Char('"'))) {
        return s.mid(1, s.size() - 2);
    }
    return s;
}

// Open a transient SQLite connection in read-only mode. Each call uses a fresh
// uuid'd connection name so re-entrant queries don't fight each other.
QSqlDatabase openRo(const QString& path) {
    if (path.isEmpty() || !QFileInfo::exists(path)) {
        return QSqlDatabase();
    }
    const QString conn = QStringLiteral("burl-emacs-%1").arg(QUuid::createUuid().toString());
    auto db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), conn);
    db.setDatabaseName(path);
    db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY;QSQLITE_OPEN_URI"));
    if (!db.open()) {
        qCWarning(lcEmacsSources) << "open failed:" << path << db.lastError().text();
        QSqlDatabase::removeDatabase(conn);
        return QSqlDatabase();
    }
    return db;
}

void closeAndRemove(QSqlDatabase& db) {
    const QString name = db.connectionName();
    db.close();
    db = QSqlDatabase();
    QSqlDatabase::removeDatabase(name);
}

} // namespace

EmacsSources::EmacsSources(QObject* parent) : QObject(parent) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(250);
    QObject::connect(&m_debounce, &QTimer::timeout, this, &EmacsSources::reload);

    QObject::connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this]() {
        // Some editors rename-on-write, breaking the watch — re-add the path.
        rewatch();
        scheduleReload();
    });

    m_stateDb = QDir::homePath() + QStringLiteral("/.config/emacs/var/emacs-state.db");
    m_roamDb = QDir::homePath() + QStringLiteral("/.config/emacs/org-roam.db");
    rewatch();
    QTimer::singleShot(0, this, &EmacsSources::reload);
}

QString EmacsSources::stateDb() const { return m_stateDb; }

void EmacsSources::setStateDb(const QString& path) {
    if (m_stateDb == path) return;
    m_stateDb = path;
    emit stateDbChanged();
    rewatch();
    loadStateDb();
}

QString EmacsSources::roamDb() const { return m_roamDb; }

void EmacsSources::setRoamDb(const QString& path) {
    if (m_roamDb == path) return;
    m_roamDb = path;
    emit roamDbChanged();
    rewatch();
    loadRoamDb();
}

int EmacsSources::recentLimit() const { return m_recentLimit; }

void EmacsSources::setRecentLimit(int n) {
    if (m_recentLimit == n) return;
    m_recentLimit = n;
    emit recentLimitChanged();
    loadStateDb();
}

QVariantList EmacsSources::recents() const { return m_recents; }
QVariantList EmacsSources::bookmarks() const { return m_bookmarks; }
QVariantList EmacsSources::projects() const { return m_projects; }
QVariantList EmacsSources::projectLinks() const { return m_projectLinks; }
QVariantList EmacsSources::roamNodes() const { return m_roamNodes; }
QVariantList EmacsSources::roamLinks() const { return m_roamLinks; }

void EmacsSources::reload() {
    loadStateDb();
    loadRoamDb();
}

void EmacsSources::rewatch() {
    if (!m_watcher.files().isEmpty()) {
        m_watcher.removePaths(m_watcher.files());
    }
    QStringList paths;
    // Watch the main DB and the WAL sidecar — in WAL mode commits land in the
    // -wal file and the main .db may not be touched until checkpoint.
    for (const QString& base : { m_stateDb, m_roamDb }) {
        if (base.isEmpty()) continue;
        for (const QString& suffix : { QStringLiteral(""), QStringLiteral("-wal") }) {
            const QString p = base + suffix;
            if (QFileInfo::exists(p)) paths << p;
        }
    }
    if (!paths.isEmpty()) m_watcher.addPaths(paths);
}

void EmacsSources::scheduleReload() {
    if (!m_debounce.isActive()) m_debounce.start();
}

void EmacsSources::loadStateDb() {
    QVariantList recents;
    QVariantList bookmarks;
    QVariantList projects;
    QVariantList projectLinks;

    auto db = openRo(m_stateDb);
    if (db.isOpen()) {
        QSqlQuery q(db);
        q.prepare(QStringLiteral(
            "SELECT file, accessed FROM recentf ORDER BY accessed DESC LIMIT ?"));
        q.addBindValue(m_recentLimit);
        if (q.exec()) {
            while (q.next()) {
                QString path = q.value(0).toString();
                if (path.startsWith(QStringLiteral("~/"))) {
                    path = QDir::homePath() + path.mid(1);
                }
                QVariantMap row;
                row.insert(QStringLiteral("kind"), QStringLiteral("recent"));
                row.insert(QStringLiteral("path"), path);
                row.insert(QStringLiteral("name"), path.section(QLatin1Char('/'), -1));
                row.insert(QStringLiteral("accessed"), q.value(1).toLongLong());
                recents.append(row);
            }
        } else {
            qCWarning(lcEmacsSources) << "recentf query:" << q.lastError().text();
        }

        QSqlQuery q2(db);
        if (q2.exec(QStringLiteral("SELECT name FROM bookmarks ORDER BY updated DESC"))) {
            while (q2.next()) {
                QVariantMap row;
                row.insert(QStringLiteral("kind"), QStringLiteral("bookmark"));
                row.insert(QStringLiteral("name"), q2.value(0).toString());
                bookmarks.append(row);
            }
        }

        // Known projects (project.el list, SQLite-backed by sn-project).
        // Schema: projects(root TEXT PRIMARY KEY, updated INTEGER).
        QSqlQuery q3(db);
        if (q3.exec(QStringLiteral("SELECT root, updated FROM projects ORDER BY updated DESC"))) {
            while (q3.next()) {
                QString root = q3.value(0).toString();
                if (root.startsWith(QStringLiteral("~/"))) {
                    root = QDir::homePath() + root.mid(1);
                }
                // project roots are dirs; trim a trailing slash for a clean name.
                const QString trimmed =
                    root.endsWith(QLatin1Char('/')) ? root.chopped(1) : root;
                QVariantMap row;
                row.insert(QStringLiteral("kind"), QStringLiteral("project"));
                row.insert(QStringLiteral("root"), root);
                row.insert(QStringLiteral("name"), trimmed.section(QLatin1Char('/'), -1));
                row.insert(QStringLiteral("updated"), q3.value(1).toLongLong());
                projects.append(row);
            }
        } else {
            // projects table may not exist on setups without sn-project — quiet.
            qCDebug(lcEmacsSources) << "projects query:" << q3.lastError().text();
        }
        closeAndRemove(db);
    }

    // Edge each recent file to the longest project root that is a prefix of
    // its path, so files cluster around the project they belong to.
    for (const QVariant& rv : recents) {
        const QString path = rv.toMap().value(QStringLiteral("path")).toString();
        QString bestRoot;
        for (const QVariant& pv : projects) {
            const QString root = pv.toMap().value(QStringLiteral("root")).toString();
            if (root.isEmpty()) continue;
            const QString rootSlash =
                root.endsWith(QLatin1Char('/')) ? root : root + QLatin1Char('/');
            if (path.startsWith(rootSlash) && root.size() > bestRoot.size()) {
                bestRoot = root;
            }
        }
        if (!bestRoot.isEmpty()) {
            QVariantMap link;
            link.insert(QStringLiteral("source"), path);
            link.insert(QStringLiteral("dest"), bestRoot);
            projectLinks.append(link);
        }
    }

    if (recents != m_recents) {
        m_recents = std::move(recents);
        emit recentsChanged();
    }
    if (bookmarks != m_bookmarks) {
        m_bookmarks = std::move(bookmarks);
        emit bookmarksChanged();
    }
    if (projects != m_projects || projectLinks != m_projectLinks) {
        m_projects = std::move(projects);
        m_projectLinks = std::move(projectLinks);
        emit projectsChanged();
    }
}

void EmacsSources::loadRoamDb() {
    QVariantList nodes;
    QVariantList links;

    auto db = openRo(m_roamDb);
    if (db.isOpen()) {
        QSqlQuery q(db);
        // GROUP_CONCAT collapses per-node tags. tags(node_id, tag); nodes(id, title, file).
        if (q.exec(QStringLiteral(
                "SELECT n.id, n.title, n.file, GROUP_CONCAT(t.tag, ',') "
                "FROM nodes n LEFT JOIN tags t ON n.id = t.node_id "
                "GROUP BY n.id ORDER BY n.title"))) {
            while (q.next()) {
                QString file = unquote(q.value(2).toString());
                if (file.startsWith(QStringLiteral("~/"))) {
                    file = QDir::homePath() + file.mid(1);
                }
                QVariantMap row;
                row.insert(QStringLiteral("kind"), QStringLiteral("roam"));
                row.insert(QStringLiteral("id"), unquote(q.value(0).toString()));
                row.insert(QStringLiteral("title"), unquote(q.value(1).toString()));
                row.insert(QStringLiteral("file"), file);
                row.insert(QStringLiteral("tags"), q.value(3).toString());
                nodes.append(row);
            }
        } else {
            qCWarning(lcEmacsSources) << "roam nodes query:" << q.lastError().text();
        }

        QSqlQuery q2(db);
        if (q2.exec(QStringLiteral("SELECT source, dest, type FROM links"))) {
            while (q2.next()) {
                QVariantMap row;
                row.insert(QStringLiteral("source"), unquote(q2.value(0).toString()));
                row.insert(QStringLiteral("dest"), unquote(q2.value(1).toString()));
                row.insert(QStringLiteral("type"), unquote(q2.value(2).toString()));
                links.append(row);
            }
        }
        closeAndRemove(db);
    }

    if (nodes != m_roamNodes) {
        m_roamNodes = std::move(nodes);
        emit roamNodesChanged();
    }
    if (links != m_roamLinks) {
        m_roamLinks = std::move(links);
        emit roamLinksChanged();
    }
}

} // namespace burl
