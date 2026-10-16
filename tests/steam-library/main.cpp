#include "../../plugin/src/Burl/Services/steamlibrary.hpp"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QElapsedTimer>
#include <QThread>
#include <QTemporaryDir>
#include <QTextStream>
#include <cstdlib>

using burl::services::steam::parseVdf;
using burl::services::steam::scan;

void check(bool result, const char* message) {
    if (!result) { qCritical("%s", message); std::exit(1); }
}
void write(const QString& path, const QByteArray& bytes) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    check(file.open(QIODevice::WriteOnly), "fixture open");
    check(file.write(bytes) == bytes.size(), "fixture write");
}
QByteArray quoted(QString value) {
    return ('"' + value.replace("\\", "\\\\").replace("\"", "\\\"") + '"').toUtf8();
}
void manifest(const QString& library, const QByteArray& id, const QByteArray& name,
              const QByteArray& install, bool installed = true) {
    write(library + "/steamapps/appmanifest_" + id + ".acf",
        "\"AppState\" { \"appid\" \"" + id + "\" \"name\" \"" + name
        + "\" \"installdir\" \"" + install + "\" }");
    if (installed) QDir().mkpath(library + "/steamapps/common/" + install);
}

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    const auto parsed = parseVdf(R"vdf(// comment
        "LibraryFolders" { "0" { "path" "/a path/with\\slash\"quote" } }
    )vdf");
    check(parsed.value("libraryfolders").toMap().value("0").toMap().value("path").toString()
        == "/a path/with\\slash\"quote", "comments and escapes");
    check(parseVdf("a { b c").isEmpty(), "truncated object rejected");
    check(parseVdf("a \"unterminated").isEmpty(), "truncated string rejected");
    check(parseVdf("a b }").isEmpty(), "unmatched close rejected");
    check(parseVdf(QByteArray(20, '{')).isEmpty(), "malformed nesting rejected");

    QTemporaryDir temp;
    check(temp.isValid(), "temporary root");
    const auto home = temp.path() + "/home";
    const auto sandbox = temp.path() + "/sandbox";
    const auto root = sandbox + "/.local/share/Steam";
    const auto external = temp.path() + "/external space";
    const auto third = sandbox + "/Games";
    QDir().mkpath(third);
    write(root + "/steamapps/libraryfolders.vdf", "libraryfolders { 0 { path "
        + quoted(home + "/.local/share/Steam") + " } 1 { path " + quoted(external)
        + " } 2 " + quoted(home + "/Games") + " }");
    manifest(root, "100", "Zelda", "Zelda");
    manifest(external, "200", "Alpha", "Alpha");
    manifest(external, "100", "duplicate", "duplicate");
    manifest(third, "300", "Sandbox game", "sandbox game");
    manifest(root, "400", "Proton Experimental", "Proton - Experimental");
    manifest(root, "401", "Steam Linux Runtime 3.0 (sniper)", "SteamLinuxRuntime_sniper");
    manifest(root, "402", "Steamworks Common Redistributables", "Steamworks Shared");
    manifest(root, "403", "Not installed", "missing", false);
    manifest(root, "404", "Traversal", "../escape", false);
    manifest(root, "4294967296", "Overflow", "overflow");
    write(root + "/steamapps/appmanifest_999.acf", "AppState { appid 123 name Wrong installdir Zelda }");
    const auto image = root + "/appcache/librarycache/100/hash/library_600x900.jpg";
    write(image, "local cover");
    auto result = scan({root, root}, home, sandbox);
    check(result.games.size() == 3, "libraries, dedup, tools and invalid manifests");
    check(result.games[0].toMap().value("appId").toString() == "200", "stable name order");
    check(result.games[2].toMap().value("imageUrl").toString().startsWith("file:"), "local hashed cover");
    check(result.watchPaths.contains(root + "/steamapps/appmanifest_100.acf"), "manifest watched");
    check(result.watchPaths.contains(external + "/steamapps"), "external directory watched");
    QFile::remove(root + "/steamapps/appmanifest_100.acf");
    result = scan({root}, home, sandbox);
    check(result.games.size() == 3, "duplicate library remains when first manifest removed");
    QFile::remove(external + "/steamapps/appmanifest_100.acf");
    check(scan({root}, home, sandbox).games.size() == 2, "removal reflected");
    qputenv("HOME", home.toUtf8());
    qputenv("XDG_DATA_HOME", (home + "/.local/share").toUtf8());
    qputenv("GUIX_SANDBOX_HOME", sandbox.toUtf8());
    burl::services::SteamLibrary service;
    int changes = 0;
    QObject::connect(&service, &burl::services::SteamLibrary::gamesChanged, [&] { ++changes; });
    const auto await = [&](const auto& condition) {
        QElapsedTimer timer;
        timer.start();
        while (!condition() && timer.elapsed() < 4000) {
            QCoreApplication::processEvents();
            QThread::msleep(5);
        }
        check(condition(), "watcher scan timed out");
    };
    await([&] { return service.games().size() == 2; });
    manifest(root, "888", "Watcher game", "watcher game");
    await([&] { return service.games().size() == 3; });
    QFile::remove(root + "/steamapps/appmanifest_888.acf");
    await([&] { return service.games().size() == 2; });
    check(changes == 3, "watcher publishes additions/removals only");
    QTextStream(stdout) << "Steam manifest/parser/watcher tests passed\n";
}
