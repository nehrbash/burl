#pragma once

#include <qfilesystemwatcher.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qstringlist.h>
#include <qtimer.h>
#include <qvariant.h>

namespace burl {

// Reads the Emacs-side sqlite DBs (org-roam + sn-state-db) and exposes their
// contents to QML as plain JS arrays of objects. Watches the files; rescans
// (debounced) when they change on disk.
class EmacsSources : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString stateDb READ stateDb WRITE setStateDb NOTIFY stateDbChanged)
    Q_PROPERTY(QString roamDb READ roamDb WRITE setRoamDb NOTIFY roamDbChanged)
    Q_PROPERTY(int recentLimit READ recentLimit WRITE setRecentLimit NOTIFY recentLimitChanged)

    Q_PROPERTY(QVariantList recents READ recents NOTIFY recentsChanged)
    Q_PROPERTY(QVariantList bookmarks READ bookmarks NOTIFY bookmarksChanged)
    Q_PROPERTY(QVariantList projects READ projects NOTIFY projectsChanged)
    // Edges: { source: recentPath, dest: projectRoot } for recents that
    // live under a known project root, so files cluster around their project.
    Q_PROPERTY(QVariantList projectLinks READ projectLinks NOTIFY projectsChanged)
    Q_PROPERTY(QVariantList roamNodes READ roamNodes NOTIFY roamNodesChanged)
    Q_PROPERTY(QVariantList roamLinks READ roamLinks NOTIFY roamLinksChanged)

public:
    explicit EmacsSources(QObject* parent = nullptr);

    [[nodiscard]] QString stateDb() const;
    void setStateDb(const QString& path);

    [[nodiscard]] QString roamDb() const;
    void setRoamDb(const QString& path);

    [[nodiscard]] int recentLimit() const;
    void setRecentLimit(int n);

    [[nodiscard]] QVariantList recents() const;
    [[nodiscard]] QVariantList bookmarks() const;
    [[nodiscard]] QVariantList projects() const;
    [[nodiscard]] QVariantList projectLinks() const;
    [[nodiscard]] QVariantList roamNodes() const;
    [[nodiscard]] QVariantList roamLinks() const;

    Q_INVOKABLE void reload();

signals:
    void stateDbChanged();
    void roamDbChanged();
    void recentLimitChanged();
    void recentsChanged();
    void bookmarksChanged();
    void projectsChanged();
    void roamNodesChanged();
    void roamLinksChanged();

private:
    void rewatch();
    void scheduleReload();
    void loadStateDb();
    void loadRoamDb();

    QString m_stateDb;
    QString m_roamDb;
    int m_recentLimit = 200;

    QVariantList m_recents;
    QVariantList m_bookmarks;
    QVariantList m_projects;
    QVariantList m_projectLinks;
    QVariantList m_roamNodes;
    QVariantList m_roamLinks;

    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};

} // namespace burl
