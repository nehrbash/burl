#include "blackbox.hpp"
#include "json.hpp"
#include "material.hpp"
#include "scheme.hpp"
#include "util.hpp"

#include <qimage.h>

using Qt::StringLiterals::operator""_s;
using blackbox::check;

namespace {

QString dataFile(const QString& relative) {
    return QStringLiteral(BURL_TEST_DATA_DIR) + u"/schemes/" + relative;
}

burl::Colours savedColours(const QString& path) {
    burl::Colours colours;
    const auto json = burl::parseJson(burl::readFile(path).toStdString());
    if (const auto* stored = json.find("colours")) {
        for (const auto& [name, code] : stored->members()) {
            colours.emplace_back(name, code.asString());
        }
    }
    return colours;
}

QString savedField(const QString& path, const char* key) {
    const auto json = burl::parseJson(burl::readFile(path).toStdString());
    const auto* value = json.find(key);
    return value ? QString::fromStdString(value->asString()) : QString();
}

QByteArray confFor(const burl::Colours& colours) {
    QByteArray conf;
    for (const auto& [name, code] : colours) {
        conf += "$" + QByteArray::fromStdString(name) + " = " + QByteArray::fromStdString(code) + "\n";
    }
    return conf;
}

void selectionIsOneCompleteWrite(const blackbox::Fixture& fixture) {
    const auto latte = fixture.run({u"scheme"_s, u"set"_s, u"-n"_s, u"catppuccin"_s, u"-f"_s, u"latte"_s});
    check(latte.exitCode == 0, u"set catppuccin latte: " + latte.err);
    check(savedField(fixture.scheme(), "name") == u"catppuccin" && savedField(fixture.scheme(), "flavour") == u"latte"
              && savedField(fixture.scheme(), "mode") == u"light",
          u"saved scheme carries the derived light mode"_s);
    check(savedColours(fixture.scheme()) == burl::readColoursFromFile(dataFile(u"catppuccin/latte/light.txt"_s)),
          u"saved colours equal catppuccin/latte/light.txt"_s);
    check(fixture.run({u"scheme"_s, u"get"_s, u"-m"_s}).out == u"light\n", u"get reports the new mode"_s);
    check(blackbox::readAll(fixture.palette()) == confFor(savedColours(fixture.scheme())),
          u"theme applied from the saved colours"_s);

    check(fixture.run({u"scheme"_s, u"set"_s, u"-n"_s, u"nocturne"_s, u"-f"_s, u"default"_s}).exitCode == 0,
          u"set nocturne default"_s);
    check(savedField(fixture.scheme(), "mode") == u"dark", u"mode follows the scheme back to dark"_s);

    const auto stateFiles = QDir(fixture.sandbox.state + u"/burl").entryList(QDir::Files | QDir::Hidden);
    check(stateFiles == QStringList({u"scheme.json"_s, u"theme.lock"_s}), u"no temporary files left: " + stateFiles.join(u","));
}

void invalidChoicePreservesSavedAndCurrentPalette(const blackbox::Fixture& fixture) {
    const auto saved = blackbox::readAll(fixture.scheme());
    const auto palette = blackbox::readAll(fixture.palette());
    check(!saved.isEmpty() && !palette.isEmpty(), u"scheme and palette saved before the invalid choices"_s);

    const QList<QStringList> invalid = {{u"-n"_s, u"unknown"_s},
                                        {u"-n"_s, u"catppuccin"_s, u"-f"_s, u"unknown"_s},
                                        {u"-n"_s, u"nocturne"_s, u"-f"_s, u"default"_s, u"-m"_s, u"light"_s}};
    for (const auto& arguments : invalid) {
        const auto label = arguments.join(u' ');
        const auto result = fixture.run(QStringList{u"scheme"_s, u"set"_s} + arguments);
        check(result.exitCode != 0 && !result.err.isEmpty(), u"set " + label + u" fails: " + result.err);
        check(blackbox::readAll(fixture.scheme()) == saved, u"saved scheme unchanged after " + label);
        check(blackbox::readAll(fixture.palette()) == palette, u"palette unchanged after " + label);
        check(fixture.run({u"scheme"_s, u"get"_s, u"-n"_s}).out == u"nocturne\n", u"current scheme unchanged after " + label);
    }
}

void dynamicFailureDoesNotChangeSelection(const blackbox::Fixture& fixture) {
    const auto saved = blackbox::readAll(fixture.scheme());
    const auto palette = blackbox::readAll(fixture.palette());
    const auto result = fixture.run({u"scheme"_s, u"set"_s, u"-n"_s, u"dynamic"_s});
    check(result.exitCode != 0 && result.err.contains(u"No wallpaper set"), u"dynamic without a wallpaper fails: " + result.err);
    check(blackbox::readAll(fixture.scheme()) == saved, u"saved scheme unchanged after dynamic failure"_s);
    check(blackbox::readAll(fixture.palette()) == palette, u"palette unchanged after dynamic failure"_s);
    check(fixture.run({u"scheme"_s, u"get"_s, u"-n"_s}).out == u"nocturne\n", u"current scheme unchanged after dynamic failure"_s);
}

void dynamicUsesCandidateConfiguration(const blackbox::Fixture& fixture) {
    QImage image(300, 200, QImage::Format_RGB32);
    image.fill(Qt::darkCyan);
    const auto wall = fixture.sandbox.root.filePath(u"wall.png"_s);
    check(image.save(wall), u"write wallpaper"_s);
    check(fixture.run({u"wallpaper"_s, u"-f"_s, wall, u"-N"_s}).exitCode == 0, u"set wallpaper"_s);

    const auto result =
        fixture.run({u"scheme"_s, u"set"_s, u"-n"_s, u"dynamic"_s, u"-f"_s, u"hard"_s, u"-m"_s, u"light"_s, u"-v"_s, u"neutral"_s});
    check(result.exitCode == 0, u"set dynamic hard light neutral: " + result.err);
    check(savedField(fixture.scheme(), "name") == u"dynamic" && savedField(fixture.scheme(), "flavour") == u"hard"
              && savedField(fixture.scheme(), "mode") == u"light" && savedField(fixture.scheme(), "variant") == u"neutral",
          u"saved dynamic scheme carries the candidate fields"_s);

    // A cache of its own, so the expected palette is generated rather than read back.
    qputenv("XDG_CONFIG_HOME", fixture.sandbox.config.toLocal8Bit());
    qputenv("XDG_STATE_HOME", fixture.sandbox.state.toLocal8Bit());
    qputenv("XDG_CACHE_HOME", fixture.sandbox.root.filePath(u"oracle-cache"_s).toLocal8Bit());
    qputenv("BURL_CLI_DATA_DIR", BURL_TEST_DATA_DIR);
    const auto paths = burl::Paths::fromEnvironment();
    const auto expected = burl::coloursForImage(paths, paths.wallpaperThumbnail, u"neutral"_s, u"hard"_s, u"light"_s);
    const auto fallback = burl::coloursForImage(paths, paths.wallpaperThumbnail, u"tonalspot"_s, u"default"_s, u"dark"_s);
    check(!expected.empty() && savedColours(fixture.scheme()) == expected, u"colours generated with the candidate configuration"_s);
    check(expected != fallback, u"candidate configuration differs from the previous one"_s);
}

} // namespace

int main(int argc, char* argv[]) {
    const QCoreApplication app(argc, argv);

    blackbox::Fixture fixture;
    check(fixture.run({u"scheme"_s, u"set"_s, u"-n"_s, u"nocturne"_s}).exitCode == 0, u"seed the saved scheme"_s);

    selectionIsOneCompleteWrite(fixture);
    invalidChoicePreservesSavedAndCurrentPalette(fixture);
    dynamicFailureDoesNotChangeSelection(fixture);
    dynamicUsesCandidateConfiguration(fixture);

    return blackbox::failures == 0 ? 0 : 1;
}
