#pragma once

#include "sandbox.hpp"

#include <qcoreapplication.h>
#include <qdir.h>
#include <qfile.h>
#include <qjsonarray.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qprocess.h>
#include <qstandardpaths.h>
#include <qtextstream.h>

namespace blackbox {

inline int failures = 0;

inline void check(bool condition, const QString& message) {
    if (!condition) {
        QTextStream(stderr) << "FAIL: " << message << "\n";
        failures++;
    }
}

inline QByteArray readAll(const QString& path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

inline void writeText(const QString& path, const QByteArray& content) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(content) != content.size()) {
        check(false, QStringLiteral("cannot write ") + path);
    }
}

inline void makeExecutable(const QString& path) {
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
}

struct Result {
    int exitCode = -1;
    QString out;
    QString err;
};

// A sandboxed burl run with only the Hyprland theme target enabled; programs
// found on PATH are the stubs in `stubs`, never the real ones.
struct Fixture {
    Sandbox sandbox;
    QString stubs;
    QProcessEnvironment environment;

    Fixture()
        : stubs(sandbox.root.filePath(QStringLiteral("stubs"))) {
        QDir().mkpath(stubs);
        environment = QProcessEnvironment::systemEnvironment();
        environment.insert(QStringLiteral("XDG_CONFIG_HOME"), sandbox.config);
        environment.insert(QStringLiteral("XDG_DATA_HOME"), sandbox.data);
        environment.insert(QStringLiteral("XDG_STATE_HOME"), sandbox.state);
        environment.insert(QStringLiteral("XDG_CACHE_HOME"), sandbox.cache);
        environment.insert(QStringLiteral("BURL_CLI_DATA_DIR"), QStringLiteral(BURL_TEST_DATA_DIR));
        for (const auto* name : {"HYPRLAND_INSTANCE_SIGNATURE", "QS_WALLPAPERS_DIR", "BURL_WALLPAPERS_DIR"}) {
            environment.remove(QString::fromLatin1(name));
        }
        environment.insert(QStringLiteral("PATH"), stubs + QStringLiteral(":") + environment.value(QStringLiteral("PATH")));

        QJsonObject theme;
        for (const auto* key : {"enableTerm", "enableDiscord", "enableSpicetify", "enablePandora", "enableSatty",
                                "enableBtop", "enableNvtop", "enableHtop", "enableQt", "enableWarp", "enableCava"}) {
            theme.insert(QString::fromLatin1(key), false);
        }
        writeText(sandbox.config + QStringLiteral("/burl/cli.json"),
                  QJsonDocument(QJsonObject{{QStringLiteral("theme"), theme}}).toJson());
    }

    [[nodiscard]] QString palette() const { return sandbox.config + QStringLiteral("/hypr/scheme/current.conf"); }
    [[nodiscard]] QString scheme() const { return sandbox.state + QStringLiteral("/burl/scheme.json"); }

    void useHyprland() { environment.insert(QStringLiteral("HYPRLAND_INSTANCE_SIGNATURE"), QStringLiteral("test-instance")); }
    void noPrograms() {
        const auto empty = sandbox.root.filePath(QStringLiteral("empty"));
        QDir().mkpath(empty);
        environment.insert(QStringLiteral("PATH"), empty);
    }

    void start(QProcess& process, const QStringList& arguments) const {
        process.setProcessEnvironment(environment);
        process.start(QStringLiteral(BURL_BINARY), arguments);
    }

    static Result finish(QProcess& process, int timeoutMs) {
        if (!process.waitForFinished(timeoutMs)) {
            process.kill();
            process.waitForFinished();
            return {-1, {}, QStringLiteral("timed out")};
        }
        return {process.exitCode(), QString::fromUtf8(process.readAllStandardOutput()),
                QString::fromUtf8(process.readAllStandardError())};
    }

    [[nodiscard]] Result run(const QStringList& arguments, int timeoutMs = 30000) const {
        QProcess process;
        start(process, arguments);
        return finish(process, timeoutMs);
    }
};

} // namespace blackbox
