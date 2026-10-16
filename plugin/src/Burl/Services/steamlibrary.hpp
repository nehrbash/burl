#pragma once

#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariant>

namespace burl::services {

namespace steam {
struct ScanResult {
    QVariantList games;
    QStringList watchPaths;
};
QVariantMap parseVdf(const QByteArray& data);
ScanResult scan(const QStringList& roots, const QString& home, const QString& sandboxHome);
}

class SteamLibrary : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList games READ games NOTIFY gamesChanged)

public:
    explicit SteamLibrary(QObject* parent = nullptr);
    QVariantList games() const { return m_games; }
    Q_INVOKABLE void refresh();

signals:
    void gamesChanged();

private:
    QVariantList m_games;
    QFileSystemWatcher m_files;
    QFutureWatcher<steam::ScanResult> m_scan;
    QTimer m_debounce;
    bool m_pending = false;
};

}
