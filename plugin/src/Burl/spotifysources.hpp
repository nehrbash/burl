#pragma once

#include <functional>
#include <memory>
#include <qelapsedtimer.h>
#include <qjsonobject.h>
#include <qset.h>
#include <qurl.h>
#include <qdatetime.h>
#include <qfilesystemwatcher.h>
#include <qnetworkaccessmanager.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qtimer.h>
#include <qvariant.h>

namespace burl {

namespace spotify {
struct PlaylistLoad {
    QString uri;
    QString id;
    quint64 authGeneration = 0;
    bool legacy = false;
    QElapsedTimer elapsed;
    QSet<QString> pages;
    QSet<QString> trackUris;
    QVariantList tracks;

    bool append(const QJsonObject& page);
};
QString playlistId(const QString& uri);
bool allowedPlaylistUrl(const QUrl& url, const QString& id, bool legacy);
QVariantMap track(const QJsonObject& object);
}


// Credentials are decrypted from the pass entry burl/spotify.
class SpotifySources : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantList playlists READ playlists NOTIFY playlistsChanged)
    Q_PROPERTY(QVariantList recents READ recents NOTIFY recentsChanged)
    Q_PROPERTY(QVariantMap playlistContents READ playlistContents NOTIFY playlistContentsChanged)
    Q_PROPERTY(bool authed READ authed NOTIFY authedChanged)

public:
    explicit SpotifySources(QObject* parent = nullptr);

    [[nodiscard]] QVariantList playlists() const { return m_playlists; }
    [[nodiscard]] QVariantList recents() const { return m_recents; }
    [[nodiscard]] bool authed() const { return !m_refreshToken.isEmpty(); }

    [[nodiscard]] QVariantMap playlistContents() const { return m_playlistContents; }
    Q_INVOKABLE void loadPlaylist(const QString& uri);
    Q_INVOKABLE void reload();
    // Begins playback of a Spotify URI on the active device. URIs
    // look like "spotify:track:...", "spotify:playlist:...", etc.
    Q_INVOKABLE void play(const QString& uri);

signals:
    void playlistsChanged();
    void recentsChanged();
    void playlistContentsChanged();
    void authedChanged();

private:
    void loadCreds(std::function<void(bool)> done = {});
    void refreshAccessToken(std::function<void(bool)> done);
    void fetchPlaylists();
    void fetchRecents();
    void fetchPlaylistPage(const std::shared_ptr<spotify::PlaylistLoad>& load, const QUrl& url);
    void finishPlaylist(const std::shared_ptr<spotify::PlaylistLoad>& load, const QString& error = {});
    bool currentPlaylistLoad(const std::shared_ptr<spotify::PlaylistLoad>& load) const;
    QNetworkRequest authed(const QString& url) const;

    QString m_passStorePath;     // ~/.password-store/burl/spotify.gpg
    QString m_clientId;
    QString m_clientSecret;
    QString m_refreshToken;
    QString m_accessToken;
    QDateTime m_accessExpiry;

    QVariantList m_playlists;
    QVariantList m_recents;
    QVariantMap m_playlistContents;
    QHash<QString, QString> m_playlistSnapshots;
    QHash<QString, std::shared_ptr<spotify::PlaylistLoad>> m_playlistLoads;
    quint64 m_authGeneration = 0;

    QNetworkAccessManager m_nam;
    QFileSystemWatcher m_watcher;
    QTimer m_refreshTimer;
    // Startup-race backoff: on system boot quickshell sometimes wins the
    // race against pam-gnupg's gpg-agent socket, so the ctor's first
    // `pass show` fails with "No such file or directory". Retry a handful
    // of times before giving up — the QML launcher-open retry then covers
    // the rare remaining case.
    QTimer m_bootRetryTimer;
    int m_bootRetriesLeft = 0;
};

} // namespace burl
