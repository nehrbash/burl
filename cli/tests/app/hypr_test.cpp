#include "blackbox.hpp"
#include "scheme.hpp"
#include "util.hpp"

#include <qelapsedtimer.h>
#include <unistd.h>

using Qt::StringLiterals::operator""_s;
using blackbox::check;

namespace {

const QByteArray oldPalette = "old palette";

// Records every call, snapshots the palette as the call saw it, and answers
// from files named for the 1-based call number.
void installHyprctl(const QString& directory) {
    const auto path = directory + u"/hyprctl";
    blackbox::writeText(path, shebang() + R"sh(d=$(dirname "$0")
printf '%s\n' "$*" >> "$d/calls"
n=$(( $(wc -l < "$d/calls") ))
cp "$XDG_CONFIG_HOME/hypr/scheme/current.conf" "$d/conf.$n" 2>/dev/null
[ -f "$d/hang.$n" ] && exec sleep 30
[ -f "$d/out.$n" ] && cat "$d/out.$n"
[ -f "$d/err.$n" ] && cat "$d/err.$n" >&2
[ -f "$d/exit.$n" ] && exit "$(cat "$d/exit.$n")"
exit 0
)sh");
    blackbox::makeExecutable(path);
}

// Holds each call open long enough for unserialised runs to overlap.
void installSlowHyprctl(const QString& directory) {
    const auto path = directory + u"/hyprctl";
    blackbox::writeText(path, shebang() + R"sh(d=$(dirname "$0")
case "$1" in -j) call=monitors ;; *) call=$1 ;; esac
echo "start $call" >> "$d/log"
sleep 0.2
echo "end $call" >> "$d/log"
[ "$call" = monitors ] && echo '[]'
exit 0
)sh");
    blackbox::makeExecutable(path);
}

void script(const blackbox::Fixture& fixture, int call, const QString& kind, const QByteArray& content) {
    blackbox::writeText(fixture.stubs + u"/" + kind + u"." + QString::number(call), content);
}

QStringList calls(const blackbox::Fixture& fixture) {
    const auto text = QString::fromUtf8(blackbox::readAll(fixture.stubs + u"/calls"));
    return text.isEmpty() ? QStringList() : text.chopped(1).split(u'\n');
}

QByteArray nordConf() {
    QByteArray conf;
    for (const auto& [name, code] : burl::readColoursFromFile(QStringLiteral(BURL_TEST_DATA_DIR) + u"/schemes/nord/medium/dark.txt")) {
        conf += "$" + QByteArray::fromStdString(name) + " = " + QByteArray::fromStdString(code) + "\n";
    }
    return conf;
}

// A fixture with the old palette in place and a stub hyprctl on PATH.
struct Case : blackbox::Fixture {
    Case() {
        blackbox::writeText(palette(), oldPalette);
        installHyprctl(stubs);
        useHyprland();
    }

    blackbox::Result apply() const { return run({u"scheme"_s, u"set"_s, u"-n"_s, u"nord"_s}); }
};

QByteArray luaEscaped(const QString& name) {
    QByteArray result = "\"";
    for (const auto byte : name.toUtf8()) {
        result += "\\" + QByteArray::number(static_cast<unsigned char>(byte)).rightJustified(3, '0');
    }
    return result + "\"";
}

void paletteReplacedAtomicallyBeforeReload() {
    Case c;
    script(c, 1, u"out"_s, "[]");
    const auto result = c.apply();
    check(result.exitCode == 0, u"apply succeeds: " + result.err);
    check(calls(c) == QStringList({u"-j monitors all"_s, u"reload"_s}), u"query then reload: " + calls(c).join(u'|'));
    check(blackbox::readAll(c.stubs + u"/conf.1") == nordConf(), u"palette complete before the query"_s);
    check(blackbox::readAll(c.stubs + u"/conf.2") == nordConf(), u"palette complete before the reload"_s);
    check(blackbox::readAll(c.palette()) == nordConf(), u"palette replaced"_s);
    check(QDir(QFileInfo(c.palette()).absolutePath()).entryList(QDir::Files | QDir::Hidden) == QStringList({u"current.conf"_s}),
          u"no temporary file left beside the palette"_s);
}

void writeFailurePreservesOldPaletteAndDoesNotReload() {
    if (geteuid() == 0) {
        QTextStream(stderr) << "SKIP: root ignores directory permissions\n";
        return;
    }
    Case c;
    const auto directory = QFileInfo(c.palette()).absolutePath();
    QFile::setPermissions(directory, QFileDevice::ReadOwner | QFileDevice::ExeOwner);
    const auto result = c.apply();
    QFile::setPermissions(directory, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);

    check(result.exitCode == 0, u"a failed palette write is logged, not fatal: " + result.err);
    check(calls(c).isEmpty(), u"no hyprctl call after a failed write: " + calls(c).join(u'|'));
    check(blackbox::readAll(c.palette()) == oldPalette, u"old palette preserved"_s);
    check(QDir(directory).entryList(QDir::Files | QDir::Hidden) == QStringList({u"current.conf"_s}), u"no temporary file left"_s);
    check(result.out.contains(u"Error during execution of \"apply_hypr()\"") && result.out.contains(u"current.conf"),
          u"write failure logged: " + result.out);
}

void offlineWriteDoesNotRequireHyprctl() {
    Case c;
    c.environment.remove(u"HYPRLAND_INSTANCE_SIGNATURE"_s);
    const auto result = c.apply();
    check(result.exitCode == 0, u"offline apply succeeds: " + result.err);
    check(calls(c).isEmpty(), u"offline apply never runs hyprctl"_s);
    check(blackbox::readAll(c.palette()) == nordConf(), u"offline palette written"_s);
    check(!result.out.contains(u"Error"), u"offline apply logs no error: " + result.out);
}

void reloadFailureLogsCompositorDiagnostic() {
    Case c;
    script(c, 1, u"out"_s, "[]");
    script(c, 2, u"err"_s, "invalid configuration");
    script(c, 2, u"exit"_s, "1");
    const auto result = c.apply();
    check(blackbox::readAll(c.palette()) == nordConf(), u"palette written before the failing reload"_s);
    check(result.out.contains(u"Hyprland reload failed: invalid configuration"), u"reload diagnostic logged: " + result.out);
}

void missingCliIsLoggedAfterPaletteWrite() {
    Case c;
    c.noPrograms();
    const auto result = c.apply();
    check(result.exitCode == 0, u"missing hyprctl is not fatal: " + result.err);
    check(blackbox::readAll(c.palette()) == nordConf(), u"palette written without hyprctl"_s);
    check(result.out.contains(u"Hyprland monitor query failed: hyprctl:"), u"missing hyprctl logged: " + result.out);
}

void reloadTimeoutIsLogged() {
    Case c;
    script(c, 1, u"out"_s, "[]");
    script(c, 2, u"hang"_s, "");
    QElapsedTimer timer;
    timer.start();
    const auto result = c.apply();
    check(timer.elapsed() < 20000, u"hung reload is cut off: %1 ms"_s.arg(timer.elapsed()));
    check(result.out.contains(u"Hyprland reload failed: timed out"), u"timeout logged: " + result.out);
    check(blackbox::readAll(c.palette()) == nordConf(), u"palette written before the timeout"_s);
}

void reloadRestoresOnlyDisabledOutputsWithSafeLuaStrings() {
    const QStringList names = {u"eDP-1"_s, QString::fromUtf8("port\"\\\n") + QChar(0) + QString::fromUtf8("\xc3\xa9; os.exit(7) --")};
    const QJsonArray monitors = {QJsonObject{{u"name"_s, u"DP-2"_s}, {u"disabled"_s, false}},
                                 QJsonObject{{u"name"_s, names[0]}, {u"disabled"_s, true}},
                                 QJsonObject{{u"name"_s, u"DP-3"_s}},
                                 QJsonObject{{u"name"_s, names[1]}, {u"disabled"_s, true}}};
    Case c;
    script(c, 1, u"out"_s, QJsonDocument(monitors).toJson());
    const auto result = c.apply();
    check(result.exitCode == 0, u"apply succeeds: " + result.err);

    const auto recorded = calls(c);
    check(recorded.size() == 4, u"query, reload and two restores: " + recorded.join(u'|'));
    if (recorded.size() != 4) {
        return;
    }
    check(recorded[0] == u"-j monitors all" && recorded[1] == u"reload", u"query then reload first"_s);
    const auto lua = QStandardPaths::findExecutable(u"lua"_s);
    for (int i = 0; i < 2; i++) {
        const auto& command = recorded[2 + i];
        const auto prefix = u"eval "_s;
        check(command.startsWith(prefix), u"restore is a Hyprland eval: " + command);
        const auto program = command.mid(prefix.size());
        const auto expected = u"hl.monitor({ output = "_s + QString::fromLatin1(luaEscaped(names[i])) + u", disabled = true })";
        check(program == expected, u"output name encoded as decimal byte escapes: " + program);
        if (lua.isEmpty()) {
            continue;
        }
        QProcess process;
        process.start(lua, {u"-e"_s,
                            u"hl = { monitor = function(t) assert(t.disabled == true); io.write(t.output) end }; "_s + program});
        check(process.waitForFinished(5000) && process.exitCode() == 0, u"restore evaluates as Lua"_s);
        check(process.readAllStandardOutput() == names[i].toUtf8(), u"Lua sees the exact output name"_s);
    }
}

void queryFailureAbortsReloadAndLogsDiagnostic() {
    Case c;
    script(c, 1, u"err"_s, "IPC unavailable");
    script(c, 1, u"exit"_s, "1");
    const auto result = c.apply();
    check(calls(c).size() == 1, u"no reload after a failed query: " + calls(c).join(u'|'));
    check(result.out.contains(u"Hyprland monitor query failed: IPC unavailable"), u"query diagnostic logged: " + result.out);
    check(blackbox::readAll(c.palette()) == nordConf(), u"palette written before the query"_s);
}

void invalidMonitorResponseAbortsReload() {
    for (const auto* response : {"not json", "{}", "[{\"disabled\":true}]"}) {
        Case c;
        script(c, 1, u"out"_s, response);
        const auto result = c.apply();
        const auto label = QString::fromLatin1(response);
        check(calls(c).size() == 1, u"no reload after response " + label + u": " + calls(c).join(u'|'));
        check(result.out.contains(u"Error during execution of \"apply_hypr()\""), u"error logged for " + label + u": " + result.out);
    }
}

void restoreAttemptsAllDisabledOutputsEvenAfterReloadFailure() {
    const QJsonArray monitors = {QJsonObject{{u"name"_s, u"eDP-1"_s}, {u"disabled"_s, true}},
                                 QJsonObject{{u"name"_s, u"DP-4"_s}, {u"disabled"_s, true}}};
    Case c;
    script(c, 1, u"out"_s, QJsonDocument(monitors).toJson());
    script(c, 2, u"err"_s, "partial reload failed");
    script(c, 2, u"exit"_s, "1");
    script(c, 3, u"err"_s, "output restore failed");
    script(c, 3, u"exit"_s, "1");
    const auto result = c.apply();
    check(calls(c).size() == 4, u"both restores attempted: " + calls(c).join(u'|'));
    check(result.out.contains(u"Hyprland reload failed: partial reload failed"), u"reload failure logged: " + result.out);
    check(result.out.contains(u"restore disabled output 'eDP-1' failed: output restore failed"),
          u"restore failure logged: " + result.out);
}

void concurrentUpdatesAreSerialisedWithoutDroppingOne() {
    blackbox::Fixture fixture;
    installSlowHyprctl(fixture.stubs);
    fixture.useHyprland();

    const QStringList schemes = {u"nord"_s, u"gruvbox"_s, u"dracula"_s};
    QProcess processes[3];
    for (int i = 0; i < 3; i++) {
        fixture.start(processes[i], {u"scheme"_s, u"set"_s, u"-n"_s, schemes[i]});
    }
    for (auto& process : processes) {
        const auto result = blackbox::Fixture::finish(process, 30000);
        check(result.exitCode == 0, u"concurrent set exits 0: " + result.err);
    }

    QStringList expected;
    for (int i = 0; i < 3; i++) {
        expected << u"start monitors"_s << u"end monitors"_s << u"start reload"_s << u"end reload"_s;
    }
    const auto log = QString::fromUtf8(blackbox::readAll(fixture.stubs + u"/log")).split(u'\n', Qt::SkipEmptyParts);
    check(log == expected, u"applies do not overlap: " + log.join(u'|'));

    const auto json = burl::parseJson(burl::readFile(fixture.scheme()).toStdString());
    burl::Colours saved;
    for (const auto& [name, code] : json.find("colours")->members()) {
        saved.emplace_back(name, code.asString());
    }
    QByteArray conf;
    for (const auto& [name, code] : saved) {
        conf += "$" + QByteArray::fromStdString(name) + " = " + QByteArray::fromStdString(code) + "\n";
    }
    check(blackbox::readAll(fixture.palette()) == conf, u"palette matches the last saved scheme"_s);
}

} // namespace

int main(int argc, char* argv[]) {
    const QCoreApplication app(argc, argv);

    paletteReplacedAtomicallyBeforeReload();
    writeFailurePreservesOldPaletteAndDoesNotReload();
    offlineWriteDoesNotRequireHyprctl();
    reloadFailureLogsCompositorDiagnostic();
    missingCliIsLoggedAfterPaletteWrite();
    reloadTimeoutIsLogged();
    reloadRestoresOnlyDisabledOutputsWithSafeLuaStrings();
    queryFailureAbortsReloadAndLogsDiagnostic();
    invalidMonitorResponseAbortsReload();
    restoreAttemptsAllDisabledOutputsEvenAfterReloadFailure();
    concurrentUpdatesAreSerialisedWithoutDroppingOne();

    return blackbox::failures == 0 ? 0 : 1;
}
