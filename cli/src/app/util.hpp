#pragma once

#include <qbytearray.h>
#include <qprocess.h>
#include <qstring.h>
#include <qstringlist.h>
#include <stdexcept>
#include <string>

namespace burl {

// Failure the user should see as a one-line message.
class Error : public std::runtime_error {
public:
    explicit Error(const std::string& message)
        : std::runtime_error(message) {}
    explicit Error(const QString& message)
        : std::runtime_error(message.toStdString()) {}
};

class FileNotFound : public Error {
public:
    using Error::Error;
};

// Writes to stdout, which the QML shell parses.
void printLine(const std::string& line);
void printLine(const QString& line);

void logMessage(const std::string& message);

// Runs `body`, logging instead of propagating any failure so the other
// theme targets still apply.
template <typename F> void logged(const char* name, F&& body) {
    try {
        body();
    } catch (const std::exception& error) {
        logMessage(std::string("Error during execution of \"") + name + "()\": " + error.what());
    }
}

QByteArray readFile(const QString& path);
void writeFileAtomic(const QString& path, const QByteArray& content);
QString sha256File(const QString& path);

// Path.suffix / Path.stem semantics: a leading dot is part of the stem.
QString pathSuffix(const QString& path);
QString pathStem(const QString& path);

struct ProcessResult {
    int exitCode = 0;
    bool timedOut = false;
    QByteArray out;
    QByteArray err;
};

// Throws Error when the program cannot start. Standard input is /dev/null and
// output is captured unless `forwardOutput` is set. A child still running after
// `timeoutMs` (-1: no limit) is killed and the result is marked timedOut.
ProcessResult runProcess(const QString& program, const QStringList& arguments, int timeoutMs = -1,
                         const QProcessEnvironment* environment = nullptr, bool forwardOutput = false);

} // namespace burl
