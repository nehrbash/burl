#include "json.hpp"
#include "sandbox.hpp"
#include "scheme.hpp"
#include "util.hpp"

#include <clocale>
#include <qcoreapplication.h>
#include <qimage.h>
#include <qjsonarray.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qprocess.h>
#include <qtextstream.h>
#include <tuple>

using Qt::StringLiterals::operator""_s;

namespace {

int failures = 0;

void check(bool condition, const QString& message) {
    if (!condition) {
        QTextStream(stderr) << "FAIL: " << message << "\n";
        failures++;
    }
}

struct Result {
    int exitCode = -1;
    QString out;
    QString err;
};

Result runBurl(const QStringList& arguments, const QProcessEnvironment* environment = nullptr) {
    QProcess process;
    if (environment) {
        process.setProcessEnvironment(*environment);
    }
    process.start(QStringLiteral(BURL_BINARY), arguments);
    if (!process.waitForFinished(30000)) {
        process.kill();
        process.waitForFinished();
        return {-1, {}, u"timed out"_s};
    }
    return {process.exitCode(), QString::fromUtf8(process.readAllStandardOutput()),
            QString::fromUtf8(process.readAllStandardError())};
}

void writeText(const QString& path, const QByteArray& content) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(content) != content.size()) {
        check(false, u"cannot write "_s + path);
    }
}

// Stand-ins for the programs the theme step and the notifier may run.
void installStubs(const QString& directory) {
    for (const auto* name : {"notify-send", "spicetify", "killall", "pass", "sass", "xdg-open"}) {
        const auto path = directory + u"/" + QString::fromLatin1(name);
        writeText(path, "#!/bin/sh\nexit 0\n");
        QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    }
    qputenv("PATH", (directory + u":"_s + qEnvironmentVariable("PATH")).toLocal8Bit());
}

QString makeImage(const QString& path, const QColor& colour) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QImage image(300, 200, QImage::Format_RGB32);
    image.fill(colour);
    check(image.save(path), u"write image "_s + path);
    return QFileInfo(path).canonicalFilePath();
}

QString linkTarget(const QString& link) {
    return QFileInfo(link).symLinkTarget();
}

// A comma-decimal locale this system provides, or empty.
QString commaLocale() {
    const auto previous = QByteArray(std::setlocale(LC_NUMERIC, nullptr));
    QString found;
    for (const auto* name : {"de_DE.UTF-8", "fr_FR.UTF-8", "es_ES.UTF-8", "pt_BR.UTF-8", "ru_RU.UTF-8", "fr_FR.utf8",
                             "es_ES.utf8", "pt_BR.utf8", "ru_RU.utf8"}) {
        if (std::setlocale(LC_NUMERIC, name) && std::localeconv()->decimal_point[0] == ',') {
            found = QString::fromLatin1(name);
            break;
        }
    }
    std::setlocale(LC_NUMERIC, previous.constData());
    return found;
}

QString dataFile(const QString& relative) {
    return QStringLiteral(BURL_TEST_DATA_DIR) + u"/schemes/" + relative;
}

} // namespace

int main(int argc, char* argv[]) {
    const QCoreApplication app(argc, argv);

    Sandbox sandbox;
    sandbox.exportEnvironment();
    qputenv("XDG_PICTURES_DIR", sandbox.root.filePath(u"pictures"_s).toLocal8Bit());
    QDir().mkpath(sandbox.root.filePath(u"stubs"_s));
    installStubs(sandbox.root.filePath(u"stubs"_s));

    // Keep the theme step from touching terminals or running programs.
    QDir().mkpath(sandbox.config + u"/burl");
    QFile cli(sandbox.config + u"/burl/cli.json");
    cli.open(QIODevice::WriteOnly);
    cli.write(R"({"theme": {"enableTerm": false, "enableSpicetify": false, "enableDiscord": false,
                 "enableBtop": false, "enableHtop": false, "enableCava": false}})");
    cli.close();

    const auto variants = runBurl({u"scheme"_s, u"list"_s, u"--variants"_s});
    check(variants.exitCode == 0, u"list --variants exits 0"_s);
    check(variants.out.split(u'\n', Qt::SkipEmptyParts) == burl::schemeVariants, u"list --variants output"_s);

    const auto modes = runBurl({u"scheme"_s, u"list"_s, u"--modes"_s});
    check(modes.exitCode == 0 && modes.out == u"dark\n", u"list --modes for the default scheme: " + modes.out);

    const auto variant = runBurl({u"scheme"_s, u"get"_s, u"-v"_s});
    check(variant.exitCode == 0 && variant.out == u"tonalspot\n", u"get -v prints the variant: " + variant.out);

    const auto summary = runBurl({u"scheme"_s, u"get"_s});
    check(summary.out.startsWith(u"Current scheme:\n    Name: nocturne\n"), u"get summary"_s);

    const auto set = runBurl({u"scheme"_s, u"set"_s, u"-n"_s, u"nord"_s});
    check(set.exitCode == 0, u"set -n nord exits 0: " + set.err);
    const auto saved = burl::parseJson(burl::readFile(sandbox.state + u"/burl/scheme.json").toStdString());
    check(saved.find("name") && saved.find("name")->asString() == "nord", u"saved name"_s);
    check(saved.find("flavour") && saved.find("flavour")->asString() == "medium", u"saved flavour"_s);
    check(saved.find("mode") && saved.find("mode")->asString() == "dark", u"saved mode"_s);
    const auto expected = burl::readColoursFromFile(dataFile(u"nord/medium/dark.txt"_s));
    burl::Colours actual;
    if (const auto* colours = saved.find("colours")) {
        for (const auto& [name, code] : colours->members()) {
            actual.emplace_back(name, code.asString());
        }
    }
    check(!expected.empty() && actual == expected, u"saved colours equal nord/medium/dark.txt"_s);
    check(QFile::exists(sandbox.config + u"/hypr/scheme/current.conf"), u"theme applied after set"_s);

    const auto flavour = runBurl({u"scheme"_s, u"set"_s, u"-n"_s, u"gruvbox"_s, u"-f"_s, u"soft"_s, u"-m"_s, u"light"_s});
    check(flavour.exitCode == 0, u"set gruvbox soft light: " + flavour.err);
    check(runBurl({u"scheme"_s, u"get"_s, u"-m"_s}).out == u"light\n", u"mode follows set"_s);

    const auto invalid = runBurl({u"scheme"_s, u"set"_s, u"-n"_s, u"nope"_s});
    check(invalid.exitCode != 0 && !invalid.err.isEmpty() && invalid.err.count(u'\n') == 1,
          u"invalid name is a one-line error: " + invalid.err);

    const auto list = runBurl({u"scheme"_s, u"list"_s});
    check(list.exitCode == 0, u"list exits 0"_s);
    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(list.out.toUtf8(), &parseError);
    check(parseError.error == QJsonParseError::NoError && document.isObject(), u"list prints one JSON object"_s);
    const auto schemes = document.object();
    check(schemes.contains(u"nord"_s) && schemes.contains(u"gruvbox"_s), u"list has the schemes"_s);
    const auto gruvbox = schemes.value(u"gruvbox"_s).toObject();
    check(gruvbox.keys() == QStringList({u"hard"_s, u"medium"_s, u"soft"_s}), u"gruvbox flavours"_s);
    const auto nord = schemes.value(u"nord"_s).toObject().value(u"medium"_s).toObject();
    const auto nordDark = burl::readColoursFromFile(dataFile(u"nord/medium/dark.txt"_s));
    bool match = nord.size() == static_cast<qsizetype>(nordDark.size());
    for (const auto& [name, code] : nordDark) {
        match = match && nord.value(QString::fromStdString(name)).toString() == QString::fromStdString(code);
    }
    check(match, u"list colours for nord"_s);
    check(schemes.value(u"dynamic"_s).toObject().isEmpty(), u"dynamic without a wallpaper is skipped"_s);

    QImage image(300, 200, QImage::Format_RGB32);
    image.fill(Qt::darkCyan);
    const auto wall = sandbox.root.filePath(u"wall.png"_s);
    check(image.save(wall), u"write test image"_s);
    const auto wallpaper = runBurl({u"wallpaper"_s, u"-f"_s, wall, u"--no-smart"_s});
    check(wallpaper.exitCode == 0, u"wallpaper -f exits 0: " + wallpaper.err);
    check(runBurl({u"wallpaper"_s}).out == QFileInfo(wall).canonicalFilePath() + u"\n", u"wallpaper prints the path"_s);
    check(QFileInfo(sandbox.state + u"/burl/wallpaper/current").isSymLink(), u"current symlink"_s);
    const QImage thumb(sandbox.state + u"/burl/wallpaper/thumbnail.jpg");
    check(thumb.size() == QSize(128, 85), u"thumbnail is 128 wide, aspect kept"_s);

    const auto state = sandbox.state + u"/burl";
    const auto currentLink = state + u"/wallpaper/current";
    const auto thumbLink = state + u"/wallpaper/thumbnail.jpg";
    const auto wall2 = makeImage(sandbox.root.filePath(u"wall2.png"_s), Qt::darkMagenta);
    const auto wallCanonical = QFileInfo(wall).canonicalFilePath();

    // An existing and a dangling `current` link are both replaced.
    check(runBurl({u"wallpaper"_s, u"-f"_s, wall2, u"-N"_s}).exitCode == 0, u"wallpaper -f over an existing link"_s);
    check(linkTarget(currentLink) == wall2, u"existing link replaced: " + linkTarget(currentLink));
    QFile::remove(currentLink);
    check(QFile::link(u"/nonexistent/wallpaper.png"_s, currentLink), u"create dangling link"_s);
    check(runBurl({u"wallpaper"_s, u"-f"_s, wallCanonical, u"-N"_s}).exitCode == 0, u"wallpaper -f over a dangling link"_s);
    check(linkTarget(currentLink) == wallCanonical, u"dangling link replaced: " + linkTarget(currentLink));
    check(!QFileInfo::exists(currentLink + u".tmp"_s), u"no temporary link left behind"_s);

    // A hook that reads stdin finishes, and sees the wallpaper path.
    const auto hookOut = sandbox.root.filePath(u"hook.out"_s);
    const QJsonObject theme{{u"enableTerm"_s, false}, {u"enableSpicetify"_s, false}, {u"enableDiscord"_s, false},
                            {u"enableBtop"_s, false}, {u"enableHtop"_s, false}, {u"enableCava"_s, false}};
    const QJsonObject hooked{{u"theme"_s, theme},
                             {u"wallpaper"_s, QJsonObject{{u"postHook"_s, u"cat; printf '%s' \"$WALLPAPER_PATH\" > '%1'"_s.arg(hookOut)}}}};
    writeText(sandbox.config + u"/burl/cli.json", QJsonDocument(hooked).toJson());
    const auto hooked1 = runBurl({u"wallpaper"_s, u"-f"_s, wall2, u"-N"_s});
    check(hooked1.exitCode == 0, u"postHook reading stdin finishes: " + hooked1.err);
    check(burl::readFile(hookOut) == wall2.toUtf8(), u"postHook receives WALLPAPER_PATH"_s);
    writeText(sandbox.config + u"/burl/cli.json", QJsonDocument(QJsonObject{{u"theme"_s, theme}}).toJson());

    // An undecodable image leaves the previous wallpaper state untouched.
    runBurl({u"wallpaper"_s, u"-f"_s, wall2, u"-N"_s});
    const auto before = std::tuple{burl::readFile(state + u"/wallpaper/path.txt"), linkTarget(currentLink),
                                   linkTarget(thumbLink), burl::readFile(state + u"/scheme.json")};
    const auto bad = sandbox.root.filePath(u"bad.png"_s);
    writeText(bad, "not an image");
    const auto failed = runBurl({u"wallpaper"_s, u"-f"_s, bad});
    check(failed.exitCode != 0 && !failed.err.isEmpty(), u"corrupt image fails: " + failed.err);
    const auto after = std::tuple{burl::readFile(state + u"/wallpaper/path.txt"), linkTarget(currentLink),
                                  linkTarget(thumbLink), burl::readFile(state + u"/scheme.json")};
    check(before == after, u"corrupt image leaves path.txt, links and scheme.json unchanged"_s);

    // `-r` skips the current wallpaper when the directory is a symlink.
    const auto realDir = sandbox.root.filePath(u"walls-real"_s);
    const auto wallA = makeImage(realDir + u"/a.png"_s, Qt::darkRed);
    const auto wallB = makeImage(realDir + u"/b.png"_s, Qt::darkGreen);
    const auto linkDir = sandbox.root.filePath(u"walls-link"_s);
    check(QFile::link(realDir, linkDir), u"create wallpaper dir link"_s);
    check(runBurl({u"wallpaper"_s, u"-f"_s, wallA, u"-N"_s}).exitCode == 0, u"seed wallpaper"_s);
    QString expectNext = wallB;
    for (int i = 0; i < 6; i++) {
        const auto random = runBurl({u"wallpaper"_s, u"-r"_s, linkDir, u"-n"_s, u"-N"_s});
        check(random.exitCode == 0, u"random exits 0: " + random.err);
        const auto shown = runBurl({u"wallpaper"_s}).out.trimmed();
        check(shown == expectNext, u"random #%1 switches to the other image: %2"_s.arg(i).arg(shown));
        expectNext = expectNext == wallB ? wallA : wallB;
    }

    // Floats in shell.json parse under a comma-decimal locale.
    const auto locale = commaLocale();
    if (locale.isEmpty()) {
        QTextStream(stderr) << "SKIP: no comma-decimal locale available\n";
    } else {
        const auto localeDir = sandbox.root.filePath(u"walls-locale"_s);
        const auto localeWall = makeImage(localeDir + u"/only.png"_s, Qt::darkYellow);
        const QByteArray shell = "{\"layout\": {\"scale\": 0.85, \"gap\": 1.5e-1}, \"paths\": {\"wallpaperDir\": \""
            + localeDir.toUtf8() + "\"}}";
        writeText(sandbox.config + u"/burl/shell.json", shell);
        auto environment = QProcessEnvironment::systemEnvironment();
        environment.insert(u"LC_ALL"_s, locale);
        const auto localised = runBurl({u"wallpaper"_s, u"-r"_s, u"-n"_s, u"-N"_s}, &environment);
        check(localised.exitCode == 0, u"random under " + locale + u": " + localised.err);
        check(runBurl({u"wallpaper"_s}).out.trimmed() == localeWall, u"shell.json wallpaperDir honoured under "_s + locale);
    }

    return failures == 0 ? 0 : 1;
}
