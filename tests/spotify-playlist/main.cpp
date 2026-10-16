#include "../../plugin/src/Burl/spotifysources.hpp"
#include <QCoreApplication>
#include <QJsonArray>
#include <QTextStream>
#include <cstdlib>

using namespace burl::spotify;
void check(bool result, const char* message) {
    if (!result) { qCritical("%s", message); std::exit(1); }
}
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    const QString id = "0123456789ABCDEFGHIJKL";
    check(playlistId("spotify:playlist:" + id) == id, "valid playlist URI");
    for (const auto& invalid : {"spotify:track:", "https://spotify.com/playlist/", "spotify:playlist:../"})
        check(playlistId(invalid + id).isEmpty(), "invalid playlist URI");
    const QString endpoint = "https://api.spotify.com/v1/playlists/" + id;
    check(allowedPlaylistUrl(QUrl(endpoint + "/items?offset=50&limit=50"), id, false), "next items page");
    check(allowedPlaylistUrl(QUrl(endpoint + "/tracks?offset=50"), id, true), "legacy page");
    for (const auto& url : {endpoint + "/tracks", endpoint + "/items/../tracks", endpoint + "/items#fragment",
                           "http://api.spotify.com/v1/playlists/" + id + "/items",
                           "https://api.spotify.com.evil.test/v1/playlists/" + id + "/items",
                           "https://user@api.spotify.com/v1/playlists/" + id + "/items",
                           "https://api.spotify.com:444/v1/playlists/" + id + "/items",
                           endpoint + "/items%2Fextra"})
        check(!allowedPlaylistUrl(QUrl(url), id, false), "untrusted pagination rejected");
    QJsonObject song{{"uri", "spotify:track:" + id}, {"name", "Song"}, {"type", "track"},
        {"artists", QJsonArray{QJsonObject{{"name", "First"}}, QJsonObject{{"name", "Second"}}}},
        {"album", QJsonObject{{"name", "Album"}, {"images", QJsonArray{QJsonObject{{"url", "https://image"}}}}}}};
    check(track(song).value("artist").toString() == "First, Second", "artist shape");
    check(track(song).value("image").toString() == "https://image", "cover shape");
    for (const auto& field : {QString("is_local"), QString("is_playable"), QString("type"), QString("restrictions")}) {
        auto excluded = song;
        if (field == "is_local") excluded[field] = true;
        if (field == "is_playable") excluded[field] = false;
        if (field == "type") excluded[field] = "episode";
        if (field == "restrictions") excluded[field] = QJsonObject{{"reason", "market"}};
        check(track(excluded).isEmpty(), "unavailable, local and episodes excluded");
    }
    PlaylistLoad load;
    check(load.append(QJsonObject{{"items", QJsonArray{QJsonObject{{"item", song}},
        QJsonObject{{"track", song}}, QJsonObject{{"item", QJsonValue::Null}}}}}), "new and legacy wrappers");
    check(load.tracks.size() == 1, "deduplicate tracks across wrappers");
    auto second = song;
    second["uri"] = "spotify:track:ABCDEFGHIJKLMNOPQRSTUV";
    check(load.append(QJsonObject{{"items", QJsonArray{QJsonObject{{"track", second}}}}}), "second page");
    check(load.tracks.size() == 2, "pages accumulate");
    check(!load.append({}), "malformed page rejected");
    QJsonArray oversized;
    for (int i = 0; i < 101; ++i) oversized.append(QJsonObject{{"track", song}});
    check(!load.append(QJsonObject{{"items", oversized}}), "page bound");
    QTextStream(stdout) << "Spotify playlist parsing and pagination validation passed\n";
}
