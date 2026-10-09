#pragma once

#include <qfilesystemwatcher.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qtimer.h>
#include <qvariant.h>

namespace burl {

// Reads Firefox / Zen Browser places.sqlite (bookmarks + history) and
// exposes the contents to QML. SQLite is opened in immutable mode via
// the file:?immutable=1 URI so we can read while the browser holds an
// exclusive lock — no copy, no risk of corruption.
//
// Bookmarks include folders (isFolder=true). bookmarkLinks gives the
// parent → child edges so the launcher graph view can render the tree.
class WebSources : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString placesDb READ placesDb WRITE setPlacesDb NOTIFY placesDbChanged)
    Q_PROPERTY(int historyLimit READ historyLimit WRITE setHistoryLimit NOTIFY historyLimitChanged)
    Q_PROPERTY(int bookmarkLimit READ bookmarkLimit WRITE setBookmarkLimit NOTIFY bookmarkLimitChanged)

    Q_PROPERTY(QVariantList bookmarks READ bookmarks NOTIFY bookmarksChanged)
    // Edges: each element is { source: bookmarkId, dest: parentBookmarkId }.
    // Only emitted for parents that are real folders the user created
    // (not the synthetic root or the top-level Menu/Toolbar/etc roots —
    // those clutter the graph).
    Q_PROPERTY(QVariantList bookmarkLinks READ bookmarkLinks NOTIFY bookmarksChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    // Edges between same-domain history entries — hub-and-spoke,
    // each entry linked to the highest-frecency entry on its host.
    Q_PROPERTY(QVariantList historyLinks READ historyLinks NOTIFY historyChanged)
    // Live tabs from sessionstore-backups/recovery.jsonlz4 (mozLZ4-
    // compressed JSON). Updated when Zen / Firefox flushes the
    // sessionstore (every ~15s by default).
    Q_PROPERTY(QVariantList tabs READ tabs NOTIFY tabsChanged)
    Q_PROPERTY(QVariantList tabLinks READ tabLinks NOTIFY tabsChanged)

public:
    explicit WebSources(QObject* parent = nullptr);

    [[nodiscard]] QString placesDb() const { return m_placesDb; }
    void setPlacesDb(const QString& path);

    [[nodiscard]] int historyLimit() const { return m_historyLimit; }
    void setHistoryLimit(int n);

    [[nodiscard]] int bookmarkLimit() const { return m_bookmarkLimit; }
    void setBookmarkLimit(int n);

    [[nodiscard]] QVariantList bookmarks() const { return m_bookmarks; }
    [[nodiscard]] QVariantList bookmarkLinks() const { return m_bookmarkLinks; }
    [[nodiscard]] QVariantList history() const { return m_history; }
    [[nodiscard]] QVariantList historyLinks() const { return m_historyLinks; }
    [[nodiscard]] QVariantList tabs() const { return m_tabs; }
    [[nodiscard]] QVariantList tabLinks() const { return m_tabLinks; }

    Q_INVOKABLE void reload();

signals:
    void placesDbChanged();
    void historyLimitChanged();
    void bookmarkLimitChanged();
    void bookmarksChanged();
    void historyChanged();
    void tabsChanged();

private:
    void rewatch();
    void scheduleReload();
    void reloadTabs();
    QString resolveDefaultPlacesDb() const;
    QString sessionstoreFor(const QString& placesDb) const;

    QString m_placesDb;
    int m_historyLimit = 500;
    int m_bookmarkLimit = 500;

    QVariantList m_bookmarks;
    QVariantList m_bookmarkLinks;
    QVariantList m_history;
    QVariantList m_historyLinks;
    QVariantList m_tabs;
    QVariantList m_tabLinks;

    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};

} // namespace burl
