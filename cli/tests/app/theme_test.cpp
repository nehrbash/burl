#include "json.hpp"
#include "paths.hpp"
#include "sandbox.hpp"
#include "theme.hpp"
#include "util.hpp"

#include <map>
#include <qcoreapplication.h>
#include <qdiriterator.h>
#include <qfile.h>
#include <qregularexpression.h>
#include <qtextstream.h>

using Qt::StringLiterals::operator""_s;

namespace {

int failures = 0;

void fail(const QString& message) {
    QTextStream(stderr) << "FAIL: " << message << "\n";
    failures++;
}

// The oracle was generated under a random /tmp/burl-oracle-*/ sandbox.
QString normalise(QString text, const QString& config) {
    static const QRegularExpression oracleConfig(uR"(/tmp/burl-oracle-[^/]+/xdg_config_home)"_s);
    return text.replace(config, u"@CONFIG@"_s).replace(oracleConfig, u"@CONFIG@"_s);
}

std::map<QString, QString> collect(const Sandbox& sandbox) {
    std::map<QString, QString> files;
    const std::pair<QString, QString> roots[] = {
        {u"XDG_CONFIG_HOME"_s, sandbox.config}, {u"XDG_DATA_HOME"_s, sandbox.data}, {u"XDG_STATE_HOME"_s, sandbox.state}};
    for (const auto& [name, root] : roots) {
        QDirIterator it(root, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const auto path = it.next();
            const auto relative = QDir(root).relativeFilePath(path);
            if (relative == u"burl/theme.lock" || relative.startsWith(u"burl/templates/")) {
                continue;
            }
            QFile file(path);
            if (!file.open(QIODevice::ReadOnly)) {
                fail(u"cannot read "_s + path);
                continue;
            }
            files[name + u"/" + relative] = normalise(QString::fromUtf8(file.readAll()), sandbox.config);
        }
    }
    return files;
}

// The runs array's elements as JSON texts: QJsonObject would sort the colour
// maps, whose order the oracle files depend on.
QList<QByteArray> splitRuns(const QByteArray& text) {
    QList<QByteArray> runs;
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    qsizetype start = 0;
    for (qsizetype i = 0; i < text.size(); i++) {
        const char c = text[i];
        if (inString) {
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                inString = false;
            }
        } else if (c == '"') {
            inString = true;
        } else if (c == '{') {
            if (depth++ == 0) {
                start = i;
            }
        } else if (c == '}' && --depth == 0) {
            runs.append(text.mid(start, i - start + 1));
        }
    }
    return runs;
}

void run(const burl::JsonValue& run, int index) {
    Sandbox sandbox;
    sandbox.exportEnvironment();

    QDir().mkpath(sandbox.config + u"/burl/templates");
    QFile sample(sandbox.config + u"/burl/templates/sample.txt");
    if (!sample.open(QIODevice::WriteOnly)) {
        fail(u"cannot create sample template"_s);
        return;
    }
    sample.write("fg={{ onSurface.hex }} bg={{ surface.rgb }} a={{ primary.hexalpha }} "
                 "ra={{ primary.rgbalpha }} mode={{ mode }} bad={{ nope.hex }} raw={{ $primary }}\n");
    sample.close();
    QDir().mkpath(sandbox.config + u"/Vencord");

    burl::Colours colours;
    for (const auto& [name, code] : run.find("colours")->members()) {
        colours.emplace_back(name, code.asString());
    }
    const auto mode = QString::fromStdString(run.find("mode")->asString());

    const auto paths = burl::Paths::fromEnvironment();
    const burl::ThemeLock lock(paths.themeLock);
    burl::applyColours(lock, paths, burl::loadUserConfig(paths), colours, mode, {.terminals = false, .commands = false});

    const auto actual = collect(sandbox);
    std::map<QString, QString> expected;
    for (const auto& [name, content] : run.find("files")->members()) {
        expected[QString::fromStdString(name)] = normalise(QString::fromStdString(content.asString()), sandbox.config);
    }

    for (const auto& [name, content] : expected) {
        const auto found = actual.find(name);
        if (found == actual.end()) {
            fail(u"run %1: missing %2"_s.arg(index).arg(name));
        } else if (found->second != content) {
            fail(u"run %1: %2 differs"_s.arg(index).arg(name));
        }
    }
    for (const auto& [name, content] : actual) {
        if (!expected.count(name)) {
            fail(u"run %1: unexpected %2"_s.arg(index).arg(name));
        }
    }
}

} // namespace

int main(int argc, char* argv[]) {
    const QCoreApplication app(argc, argv);

    const auto runs = splitRuns(burl::readFile(QStringLiteral(BURL_ORACLE_FILE)));
    if (runs.isEmpty()) {
        fail(u"oracle has no runs"_s);
    }
    int index = 0;
    for (const auto& text : runs) {
        run(burl::parseJson(text.toStdString()), index++);
    }
    return failures == 0 ? 0 : 1;
}
