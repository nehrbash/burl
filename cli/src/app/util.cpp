#include "util.hpp"

#include <cstdio>
#include <iostream>
#include <qcryptographichash.h>
#include <qdatetime.h>
#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qsavefile.h>

using Qt::StringLiterals::operator""_s;

namespace burl {

void printLine(const std::string& line) {
    std::fwrite(line.data(), 1, line.size(), stdout);
    std::fputc('\n', stdout);
}

void printLine(const QString& line) {
    printLine(line.toStdString());
}

void logMessage(const std::string& message) {
    const auto timestamp = QDateTime::currentDateTime().toString(u"yyyy-MM-dd HH:mm:ss"_s);
    printLine("[" + timestamp.toStdString() + "] " + message);
}

QByteArray readFile(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        const auto message = path + ": " + file.errorString();
        if (file.error() == QFileDevice::OpenError && !QFileInfo::exists(path)) {
            throw FileNotFound(message);
        }
        throw Error(message);
    }
    return file.readAll();
}

void writeFileAtomic(const QString& path, const QByteArray& content) {
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) {
        throw Error(path + ": cannot create directory");
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(content) != content.size() || !file.commit()) {
        throw Error(path + ": " + file.errorString());
    }
}

QString sha256File(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        const auto message = path + ": " + file.errorString();
        if (!QFileInfo::exists(path)) {
            throw FileNotFound(message);
        }
        throw Error(message);
    }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    hash.addData(&file);
    return QString::fromLatin1(hash.result().toHex());
}

QString pathSuffix(const QString& path) {
    const auto name = QFileInfo(path).fileName();
    const auto dot = name.lastIndexOf(u'.');
    if (dot <= 0 || dot == name.size() - 1) {
        return {};
    }
    return name.mid(dot);
}

QString pathStem(const QString& path) {
    const auto name = QFileInfo(path).fileName();
    return name.chopped(pathSuffix(path).size());
}

ProcessResult runProcess(const QString& program, const QStringList& arguments, int timeoutMs,
                         const QProcessEnvironment* environment, bool forwardOutput) {
    QProcess process;
    if (environment) {
        process.setProcessEnvironment(*environment);
    }
    process.setStandardInputFile(QProcess::nullDevice());
    if (forwardOutput) {
        process.setProcessChannelMode(QProcess::ForwardedOutputChannel);
    }
    process.start(program, arguments);
    if (!process.waitForStarted()) {
        throw Error(program + ": " + process.errorString());
    }

    ProcessResult result;
    if (!process.waitForFinished(timeoutMs)) {
        result.timedOut = true;
        process.kill();
        process.waitForFinished();
    }
    result.exitCode = process.exitCode();
    result.out = process.readAllStandardOutput();
    result.err = process.readAllStandardError();
    return result;
}

} // namespace burl
