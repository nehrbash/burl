// One-time Spotify OAuth setup for burl.
//
// Reads SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET (or argv[1] / argv[2]), opens
// the browser, catches the redirect on 127.0.0.1:8888/callback and stores the
// credentials plus refresh token in `pass` under burl/spotify. The shell's
// SpotifySources component reads that entry with `pass show`.
//
// The app's Redirect URI in developer.spotify.com/dashboard must be exactly
// http://127.0.0.1:8888/callback

#include <qbytearray.h>
#include <qcoreapplication.h>
#include <qhostaddress.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qnetworkaccessmanager.h>
#include <qnetworkreply.h>
#include <qnetworkrequest.h>
#include <qprocess.h>
#include <qrandom.h>
#include <qstringlist.h>
#include <qtcpserver.h>
#include <qtcpsocket.h>
#include <qtimer.h>
#include <qurl.h>
#include <qurlquery.h>

#include <cstdio>

namespace {

constexpr auto kRedirectUri = "http://127.0.0.1:8888/callback";
constexpr auto kPassEntry = "burl/spotify";
constexpr int kTimeoutMs = 180'000;
constexpr quint16 kPort = 8888;
constexpr qsizetype kMaxRequestBytes = 8 * 1024;

const QStringList kScopes = {
    QStringLiteral("playlist-read-private"),
    QStringLiteral("playlist-read-collaborative"),
    QStringLiteral("user-read-recently-played"),
    QStringLiteral("user-top-read"),
    QStringLiteral("user-read-playback-state"),
    QStringLiteral("user-modify-playback-state"),
    QStringLiteral("user-library-read"),
};

[[noreturn]] void die(const QString& message) {
    std::fprintf(stderr, "%s\n", qPrintable(message));
    std::fflush(stderr);
    std::exit(1);
}

QByteArray encode(const QString& s) {
    return QUrl::toPercentEncoding(s);
}

QByteArray formBody(const QList<QPair<QString, QString>>& fields) {
    QByteArray body;
    for (const auto& [key, value] : fields) {
        if (!body.isEmpty()) {
            body += '&';
        }
        body += encode(key) + '=' + encode(value);
    }
    return body;
}

QString randomState() {
    QByteArray bytes(16, Qt::Uninitialized);
    for (qsizetype i = 0; i < bytes.size(); ++i) {
        bytes[i] = static_cast<char>(QRandomGenerator::system()->bounded(256));
    }
    return QString::fromLatin1(
        bytes.toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
}

QString authorizeUrl(const QString& clientId, const QString& state) {
    // Spaces as '+' in the query, matching the form encoding Spotify expects.
    const QByteArray scope = encode(kScopes.join(QLatin1Char(' '))).replace("%20", "+");
    QByteArray query = formBody({
        {QStringLiteral("client_id"), clientId},
        {QStringLiteral("response_type"), QStringLiteral("code")},
        {QStringLiteral("redirect_uri"), QString::fromLatin1(kRedirectUri)},
    });
    query += "&scope=" + scope + "&state=" + encode(state);
    return QStringLiteral("https://accounts.spotify.com/authorize?") + QString::fromLatin1(query);
}

// Serves 127.0.0.1:8888 until a /callback request carries a code, then stops
// listening and ignores everything else.
class CallbackServer : public QObject {
    Q_OBJECT
public:
    explicit CallbackServer(QObject* parent = nullptr) : QObject(parent) {
        connect(&m_server, &QTcpServer::newConnection, this, &CallbackServer::accept);
    }

    bool listen() {
        return m_server.listen(QHostAddress::LocalHost, kPort);
    }
    QString errorString() const {
        return m_server.errorString();
    }

signals:
    void received(const QString& code, const QString& state);

private:
    void accept() {
        while (QTcpSocket* socket = m_server.nextPendingConnection()) {
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            connect(socket, &QTcpSocket::readyRead, this, [this, socket]() { read(socket); });
        }
    }

    void read(QTcpSocket* socket) {
        if (m_done) {
            socket->abort();
            return;
        }
        QByteArray request = socket->property("buffer").toByteArray() + socket->readAll();
        if (request.size() > kMaxRequestBytes) {
            socket->abort();
            return;
        }
        const qsizetype end = request.indexOf("\n\n") >= 0 ? request.indexOf("\n\n")
                                                          : request.indexOf("\r\n\r\n");
        if (end < 0) {
            socket->setProperty("buffer", request);
            return;
        }
        socket->setProperty("buffer", QByteArray());
        respond(socket, request.left(request.indexOf('\n')).trimmed());
    }

    void respond(QTcpSocket* socket, const QByteArray& requestLine) {
        const QList<QByteArray> parts = requestLine.split(' ');
        const QUrl target = parts.size() >= 2 ? QUrl::fromEncoded(parts.at(1)) : QUrl();
        if (parts.value(0) != "GET" || target.path() != QStringLiteral("/callback")) {
            reply(socket, "404 Not Found", {});
            return;
        }

        const QUrlQuery query(target);
        const QString code = query.queryItemValue(QStringLiteral("code"), QUrl::FullyDecoded);
        const QString state = query.queryItemValue(QStringLiteral("state"), QUrl::FullyDecoded);
        reply(socket, "200 OK",
              "<html><body><h2>Spotify connected.</h2>"
              "<p>You can close this tab.</p></body></html>");
        // A callback without a code (denied consent) keeps waiting.
        if (!code.isEmpty()) {
            m_done = true;
            m_server.close();
            emit received(code, state);
        }
    }

    static void reply(QTcpSocket* socket, const QByteArray& status, const QByteArray& body) {
        QByteArray out = "HTTP/1.0 " + status + "\r\n";
        if (!body.isEmpty()) {
            out += "Content-Type: text/html; charset=utf-8\r\n";
        }
        out += "Content-Length: " + QByteArray::number(body.size()) + "\r\n\r\n" + body;
        socket->write(out);
        socket->disconnectFromHost();
    }

    QTcpServer m_server;
    bool m_done = false;
};

void storeCredentials(const QString& clientId, const QString& secret, const QString& refresh) {
    const QJsonObject object{
        {QStringLiteral("client_id"), clientId},
        {QStringLiteral("client_secret"), secret},
        {QStringLiteral("refresh_token"), refresh},
    };
    const QByteArray payload = QJsonDocument(object).toJson(QJsonDocument::Indented);

    // `pass insert -m` reads the multi-line entry from stdin, terminated by
    // EOF. `-f` overwrites any existing entry of the same name.
    QProcess pass;
    pass.setProcessChannelMode(QProcess::ForwardedChannels);
    pass.start(QStringLiteral("pass"),
               {QStringLiteral("insert"), QStringLiteral("-m"), QStringLiteral("-f"),
                QString::fromLatin1(kPassEntry)});
    if (!pass.waitForStarted()) {
        die(QStringLiteral("failed to run pass: %1").arg(pass.errorString()));
    }
    pass.write(payload);
    pass.closeWriteChannel();
    pass.waitForFinished(-1);
    if (pass.exitStatus() != QProcess::NormalExit || pass.exitCode() != 0) {
        die(QStringLiteral("pass insert failed (exit %1)").arg(pass.exitCode()));
    }
    std::printf("stored credentials in pass: %s\n", kPassEntry);
}

} // namespace

int main(int argc, char* argv[]) {
    QCoreApplication app(argc, argv);

    const QStringList args = QCoreApplication::arguments();
    const QString envId = qEnvironmentVariable("SPOTIFY_CLIENT_ID");
    const QString envSecret = qEnvironmentVariable("SPOTIFY_CLIENT_SECRET");
    const QString clientId = !envId.isEmpty() ? envId : args.value(1);
    const QString secret = !envSecret.isEmpty() ? envSecret : args.value(2);
    if (clientId.isEmpty() || secret.isEmpty()) {
        die(QStringLiteral("missing client id/secret — set SPOTIFY_CLIENT_ID and "
                           "SPOTIFY_CLIENT_SECRET, or pass them as args"));
    }

    const QString state = randomState();
    const QString url = authorizeUrl(clientId, state);

    CallbackServer server;
    if (!server.listen()) {
        die(QStringLiteral("cannot listen on 127.0.0.1:%1: %2").arg(kPort).arg(server.errorString()));
    }

    QNetworkAccessManager network;
    QString code;

    QTimer timeout;
    timeout.setSingleShot(true);
    QObject::connect(&timeout, &QTimer::timeout, &app,
                     []() { die(QStringLiteral("no auth code received (timed out)")); });

    QObject::connect(&server, &CallbackServer::received, &app,
                     [&](const QString& receivedCode, const QString& receivedState) {
        timeout.stop();
        if (receivedState != state) {
            die(QStringLiteral("state mismatch — possible csrf, abort"));
        }
        code = receivedCode;

        QNetworkRequest request(QUrl(QStringLiteral("https://accounts.spotify.com/api/token")));
        request.setRawHeader("Authorization",
                             "Basic " + QStringLiteral("%1:%2").arg(clientId, secret).toUtf8().toBase64());
        request.setHeader(QNetworkRequest::ContentTypeHeader,
                          QStringLiteral("application/x-www-form-urlencoded"));
        QNetworkReply* reply = network.post(
            request, formBody({
                         {QStringLiteral("grant_type"), QStringLiteral("authorization_code")},
                         {QStringLiteral("code"), code},
                         {QStringLiteral("redirect_uri"), QString::fromLatin1(kRedirectUri)},
                     }));
        QObject::connect(reply, &QNetworkReply::finished, &app, [&, reply]() {
            const QByteArray data = reply->readAll();
            const QJsonObject body = QJsonDocument::fromJson(data).object();
            if (reply->error() != QNetworkReply::NoError) {
                // Error bodies carry only the `error` fields, never credentials.
                const QString detail = body.value(QStringLiteral("error_description")).toString();
                die(QStringLiteral("token request failed: %1%2")
                        .arg(reply->errorString(),
                             detail.isEmpty() ? QString() : QStringLiteral(" (%1)").arg(detail)));
            }

            const QString refresh = body.value(QStringLiteral("refresh_token")).toString();
            if (refresh.isEmpty()) {
                die(QStringLiteral("no refresh_token in response"));
            }
            storeCredentials(clientId, secret, refresh);
            QCoreApplication::exit(0);
        });
    });

    timeout.start(kTimeoutMs);

    std::printf("opening browser: %s\n", qPrintable(url));
    std::fflush(stdout);
    if (!QProcess::startDetached(QStringLiteral("xdg-open"), {url})) {
        std::fprintf(stderr, "could not run xdg-open; open the URL above manually\n");
    }

    return QCoreApplication::exec();
}

#include "main.moc"
