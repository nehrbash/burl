#pragma once

#include <QtQuick/qquickitem.h>
#include <qhash.h>
#include <qlist.h>
#include <qobject.h>
#include <qqmlintegration.h>

namespace burl {

class CUtils : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT)

public:
    // clang-format off
    Q_INVOKABLE void saveItem(QQuickItem* target, const QUrl& path);
    Q_INVOKABLE void saveItem(QQuickItem* target, const QUrl& path, const QRect& rect);
    Q_INVOKABLE void saveItem(QQuickItem* target, const QUrl& path, QJSValue onSaved);
    Q_INVOKABLE void saveItem(QQuickItem* target, const QUrl& path, QJSValue onSaved, QJSValue onFailed);
    Q_INVOKABLE void saveItem(QQuickItem* target, const QUrl& path, const QRect& rect, QJSValue onSaved);
    Q_INVOKABLE void saveItem(QQuickItem* target, const QUrl& path, const QRect& rect, QJSValue onSaved, QJSValue onFailed);
    // clang-format on

    Q_INVOKABLE static bool copyFile(const QUrl& source, const QUrl& target, bool overwrite = true);
    Q_INVOKABLE static bool deleteFile(const QUrl& path);
    Q_INVOKABLE static QString toLocalFile(const QUrl& url);

    Q_INVOKABLE static qreal clamp(qreal value, qreal min, qreal max);

    Q_INVOKABLE static QQuickItem* findChild(QQuickItem* root, const QString& name);
    Q_INVOKABLE static QList<QQuickItem*> findChildren(QQuickItem* root, const QString& name);
    Q_INVOKABLE static QList<QQuickItem*> findChildrenMatching(QQuickItem* root, const QString& pattern);

    // Look up the burl-generated thumbnail for a wallpaper path.
    // Hash is sha256 of the file *content* — matches burl.utils.paths
    // .compute_hash so we can reuse the python CLI's cache without
    // recomputing thumbnails. Returns "" if no thumbnail exists yet.
    Q_INVOKABLE QString wallpaperThumbnail(const QString& imagePath) const;

    [[nodiscard]] QString version() const;
    [[nodiscard]] QString qtVersion() const;

private:
    // The content hash means a cache miss costs a full file read on the GUI
    // thread, and this is called from an Image.source binding once per
    // wallpaper delegate on every graph rebuild. Memoised on (mtime, size):
    // a wallpaper whose bytes changed always changes at least one of them.
    struct ThumbEntry {
        qint64 mtimeMs;
        qint64 size;
        QString thumbnail;
    };

    mutable QHash<QString, ThumbEntry> m_thumbnailCache;
};

} // namespace burl
