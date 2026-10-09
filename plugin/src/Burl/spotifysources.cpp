#include "spotifysources.hpp"

#include <qbytearray.h>
#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qjsonarray.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qloggingcategory.h>
#include <qnetworkreply.h>
#include <qprocess.h>
#include <QtCore/QProcessEnvironment>
#include <qstandardpaths.h>
#include <qurl.h>
#include <qurlquery.h>

Q_LOGGING_CATEGORY(lcSpotify, "burl.spotify", QtInfoMsg)

using Qt::StringLiterals::operator""_s;

namespace burl {

SpotifySources::SpotifySources(QObject* parent) : QObject(parent) {
    // Credentials live in `pass` under `burl/spotify`. The
    // password-store backing file is GPG-encrypted on disk at
    // ~/.password-store/burl/spotify.gpg — we watch that file so
    // re-running `burl-spotify-auth` is picked up automatically.
    const QString env = QProcessEnvironment::systemEnvironment().value(u"PASSWORD_STORE_DIR"_s);
    const QString storeRoot = env.isEmpty()
        ? (QDir::homePath() + u"/.password-store"_s)
        : env;
    m_passStorePath = storeRoot + u"/burl/spotify.gpg"_s;

    if (QFileInfo::exists(m_passStorePath)) m_watcher.addPath(m_passStorePath);
    QObject::connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this]() {
        if (!m_watcher.files().contains(m_passStorePath) && QFileInfo::exists(m_passStorePath))
            m_watcher.addPath(m_passStorePath);
        loadCreds([this](bool ok) { if (ok) reload(); });
    });

    // Periodically refresh playlists + recents — Spotify doesn't push.
    // 10 minutes is fine; the user kicks reload() manually on launcher
    // open via the QML side if they want sooner.
    m_refreshTimer.setInterval(10 * 60 * 1000);
    QObject::connect(&m_refreshTimer, &QTimer::timeout, this, &SpotifySources::reload);

    // Schedule retries on boot — gpg-agent may take several seconds to
    // appear after greetd/pam-gnupg. 5 tries at 2s/4s/8s/16s/32s covers
    // ~1 minute, well past typical agent-ready latency.
    m_bootRetryTimer.setSingleShot(true);
    QObject::connect(&m_bootRetryTimer, &QTimer::timeout, this, [this]() {
        loadCreds([this](bool ok) {
            if (ok) {
                if (!m_refreshTimer.isActive()) m_refreshTimer.start();
                refreshAccessToken([this](bool ok) {
                    if (!ok) return;
                    fetchPlaylists();
                    fetchRecents();
                });
                return;
            }
            if (m_bootRetriesLeft-- > 0)
                m_bootRetryTimer.start(m_bootRetryTimer.interval() * 2);
        });
    });

    m_bootRetriesLeft = 5;
    loadCreds([this](bool ok) {
        if (ok) {
            m_refreshTimer.start();
            reload();
            return;
        }
        m_bootRetryTimer.start(2000);
    });
}

void SpotifySources::loadCreds(std::function<void(bool)> done) {
    const bool wasAuthed = !m_refreshToken.isEmpty();
    m_clientId.clear();
    m_clientSecret.clear();
    m_refreshToken.clear();

    if (!QFileInfo::exists(m_passStorePath)) {
        if (wasAuthed) emit authedChanged();
        if (done) done(false);
        return;
    }

    // `pass show burl/spotify` decrypts via the user's GPG agent.
    // Run async — calling this synchronously from reload() would block
    // the Qt event loop (up to 5s) and stall the launcher-open animation
    // whenever the agent isn't ready yet.
    auto* p = new QProcess(this);
    // Never let this background reader pop an interactive pinentry: burl can start
    // before pam-gnupg presets gpg-agent's passphrase (~8s race), and a blocking
    // pinentry here is the "unlock OpenPGP key" dialog. Force gpg to fail fast
    // instead — the ctor's boot-retry ladder (2/4/8/16/32s) succeeds once pam's preset lands.
    auto penv = QProcessEnvironment::systemEnvironment();
    penv.insert(u"PASSWORD_STORE_GPG_OPTS"_s, u"--pinentry-mode=cancel"_s);
    p->setProcessEnvironment(penv);
    QObject::connect(p, &QProcess::finished, this,
        [this, p, wasAuthed, done](int code, QProcess::ExitStatus) {
            p->deleteLater();
            if (code != 0) {
                qCWarning(lcSpotify) << "pass show failed:" << code
                                     << p->readAllStandardError();
                if (wasAuthed) emit authedChanged();
                if (done) done(false);
                return;
            }
            const auto obj = QJsonDocument::fromJson(p->readAllStandardOutput()).object();
            m_clientId = obj.value(u"client_id"_s).toString();
            m_clientSecret = obj.value(u"client_secret"_s).toString();
            m_refreshToken = obj.value(u"refresh_token"_s).toString();
            if (wasAuthed != !m_refreshToken.isEmpty()) emit authedChanged();
            if (done) done(!m_refreshToken.isEmpty());
        });
    p->start(u"pass"_s, { u"show"_s, u"burl/spotify"_s });
}

QNetworkRequest SpotifySources::authed(const QString& url) const {
    QNetworkRequest req((QUrl(url)));
    req.setRawHeader("Authorization", ("Bearer " + m_accessToken).toUtf8());
    req.setRawHeader("Accept", "application/json");
    return req;
}

void SpotifySources::refreshAccessToken(std::function<void(bool)> done) {
    if (m_refreshToken.isEmpty()) {
        done(false);
        return;
    }
    if (!m_accessToken.isEmpty() && QDateTime::currentDateTime() < m_accessExpiry.addSecs(-30)) {
        done(true);
        return;
    }
    QNetworkRequest req((QUrl(u"https://accounts.spotify.com/api/token"_s)));
    req.setHeader(QNetworkRequest::ContentTypeHeader, u"application/x-www-form-urlencoded"_s);
    const QByteArray basic = (m_clientId + u":"_s + m_clientSecret).toUtf8().toBase64();
    req.setRawHeader("Authorization", "Basic " + basic);

    QUrlQuery body;
    body.addQueryItem(u"grant_type"_s, u"refresh_token"_s);
    body.addQueryItem(u"refresh_token"_s, m_refreshToken);
    const QByteArray payload = body.toString(QUrl::FullyEncoded).toUtf8();

    auto* reply = m_nam.post(req, payload);
    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply, done]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(lcSpotify) << "token refresh failed:" << reply->errorString();
            done(false);
            return;
        }
        const auto obj = QJsonDocument::fromJson(reply->readAll()).object();
        m_accessToken = obj.value(u"access_token"_s).toString();
        const int expiresIn = obj.value(u"expires_in"_s).toInt(3600);
        m_accessExpiry = QDateTime::currentDateTime().addSecs(expiresIn);
        // Spotify occasionally returns a new refresh_token — pick it up.
        const QString rt = obj.value(u"refresh_token"_s).toString();
        if (!rt.isEmpty()) m_refreshToken = rt;
        done(!m_accessToken.isEmpty());
    });
}

void SpotifySources::reload() {
    // Retry loadCreds if we never auth'd — the ctor's first `pass show` can lose the
    // gpg-agent startup race. Calling reload() (e.g. on launcher open) gives it another chance.
    if (m_refreshToken.isEmpty()) {
        loadCreds([this](bool ok) {
            if (!ok) return;
            if (!m_refreshTimer.isActive()) m_refreshTimer.start();
            refreshAccessToken([this](bool ok) {
                if (!ok) return;
                fetchPlaylists();
                fetchRecents();
            });
        });
        return;
    }
    refreshAccessToken([this](bool ok) {
        if (!ok) return;
        fetchPlaylists();
        fetchRecents();
    });
}

void SpotifySources::fetchPlaylists() {
    auto* reply = m_nam.get(authed(u"https://api.spotify.com/v1/me/playlists?limit=50"_s));
    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(lcSpotify) << "playlists fetch failed:" << reply->errorString();
            return;
        }
        const auto obj = QJsonDocument::fromJson(reply->readAll()).object();
        QVariantList out;
        for (const auto& v : obj.value(u"items"_s).toArray()) {
            const auto p = v.toObject();
            QVariantMap m;
            m[u"uri"_s] = p.value(u"uri"_s).toString();
            m[u"name"_s] = p.value(u"name"_s).toString();
            m[u"owner"_s] = p.value(u"owner"_s).toObject().value(u"display_name"_s).toString();
            const auto images = p.value(u"images"_s).toArray();
            m[u"image"_s] = images.isEmpty() ? QString() : images.first().toObject().value(u"url"_s).toString();
            const auto tracks = p.value(u"tracks"_s).toObject();
            m[u"trackCount"_s] = tracks.value(u"total"_s).toInt();
            out.append(m);
        }
        m_playlists = std::move(out);
        emit playlistsChanged();
    });
}

void SpotifySources::fetchRecents() {
    auto* reply = m_nam.get(authed(u"https://api.spotify.com/v1/me/player/recently-played?limit=50"_s));
    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(lcSpotify) << "recents fetch failed:" << reply->errorString();
            return;
        }
        const auto obj = QJsonDocument::fromJson(reply->readAll()).object();
        QVariantList out;
        for (const auto& v : obj.value(u"items"_s).toArray()) {
            const auto t = v.toObject().value(u"track"_s).toObject();
            QVariantMap m;
            m[u"uri"_s] = t.value(u"uri"_s).toString();
            m[u"name"_s] = t.value(u"name"_s).toString();
            const auto artists = t.value(u"artists"_s).toArray();
            QStringList names;
            for (const auto& a : artists)
                names << a.toObject().value(u"name"_s).toString();
            m[u"artist"_s] = names.join(u", "_s);
            const auto album = t.value(u"album"_s).toObject();
            m[u"album"_s] = album.value(u"name"_s).toString();
            const auto images = album.value(u"images"_s).toArray();
            m[u"image"_s] = images.isEmpty() ? QString() : images.first().toObject().value(u"url"_s).toString();
            out.append(m);
        }
        m_recents = std::move(out);
        emit recentsChanged();
    });
}

void SpotifySources::play(const QString& uri) {
    if (uri.isEmpty() || m_refreshToken.isEmpty()) return;
    refreshAccessToken([this, uri](bool ok) {
        if (!ok) return;

        // First check the device list — Spotify only accepts /play if
        // *something* is connected (desktop app, phone, speaker). If
        // there's no device at all, launch the desktop app and retry
        // a second later; if there is one but it's not active, pass
        // its id explicitly so Spotify wakes it up.
        auto* devices = m_nam.get(authed(u"https://api.spotify.com/v1/me/player/devices"_s));
        QObject::connect(devices, &QNetworkReply::finished, this, [this, devices, uri]() {
            devices->deleteLater();
            QString deviceId;
            if (devices->error() == QNetworkReply::NoError) {
                const auto obj = QJsonDocument::fromJson(devices->readAll()).object();
                const auto arr = obj.value(u"devices"_s).toArray();
                // Prefer the active one; else the first.
                for (const auto& v : arr) {
                    const auto d = v.toObject();
                    if (d.value(u"is_active"_s).toBool()) {
                        deviceId = d.value(u"id"_s).toString();
                        break;
                    }
                }
                if (deviceId.isEmpty() && !arr.isEmpty())
                    deviceId = arr.first().toObject().value(u"id"_s).toString();
            }

            if (deviceId.isEmpty()) {
                // No device at all — launch the desktop client. The
                // user's first click will fail, but the next one (a
                // few seconds after Spotify finishes opening) works.
                qCInfo(lcSpotify) << "no Spotify device — launching desktop app";
                QProcess::startDetached(u"sh"_s, { u"-c"_s, u"xdg-open spotify://"_s });
                return;
            }

            QUrl url(u"https://api.spotify.com/v1/me/player/play"_s);
            QUrlQuery q;
            q.addQueryItem(u"device_id"_s, deviceId);
            url.setQuery(q);
            QNetworkRequest req(url);
            req.setRawHeader("Authorization", ("Bearer " + m_accessToken).toUtf8());
            req.setHeader(QNetworkRequest::ContentTypeHeader, u"application/json"_s);

            QJsonObject body;
            // Tracks need "uris": [...] — playlists/albums need "context_uri".
            if (uri.startsWith(u"spotify:track:"_s)) {
                body.insert(u"uris"_s, QJsonArray{ uri });
            } else {
                body.insert(u"context_uri"_s, uri);
            }
            const QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);

            auto* reply = m_nam.sendCustomRequest(req, "PUT", payload);
            QObject::connect(reply, &QNetworkReply::finished, this, [reply]() {
                if (reply->error() != QNetworkReply::NoError) {
                    qCWarning(lcSpotify) << "play failed:" << reply->errorString()
                                         << reply->readAll();
                }
                reply->deleteLater();
            });
        });
    });
}

} // namespace burl
