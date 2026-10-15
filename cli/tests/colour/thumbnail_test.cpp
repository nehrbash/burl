#include "colour/colour.hpp"

#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>

#include <cstdio>
#include <exception>

namespace {

QByteArray read(const QString& name) {
    QFile file(QString::fromLatin1(BURL_THUMBNAIL_DIR) + "/" + name);
    if (!file.open(QIODevice::ReadOnly)) {
        std::fprintf(stderr, "cannot open %s\n", qPrintable(file.fileName()));
        std::exit(2);
    }

    return file.readAll();
}

} // namespace

int main() {
    const auto cases = QJsonDocument::fromJson(read(QStringLiteral("thumbnails.json"))).array();
    int failures = 0;
    for (const auto& value : cases) {
        const auto object = value.toObject();
        const auto source = object.value(QStringLiteral("source")).toString();
        const auto expected = read(object.value(QStringLiteral("thumbnail")).toString());
        try {
            const auto bytes = burl::colour::thumbnailJpeg(
                (QString::fromLatin1(BURL_THUMBNAIL_DIR) + "/" + source).toStdString());
            const QByteArray got(reinterpret_cast<const char*>(bytes.data()), static_cast<qsizetype>(bytes.size()));
            if (got != expected) {
                ++failures;
                std::fprintf(stderr, "%s: thumbnail differs (expected %lld bytes, got %lld)\n", qPrintable(source),
                    static_cast<long long>(expected.size()), static_cast<long long>(got.size()));
            }
        } catch (const std::exception& error) {
            ++failures;
            std::fprintf(stderr, "%s: %s\n", qPrintable(source), error.what());
        }
    }

    if (failures == 0) {
        std::printf("%lld thumbnails match\n", static_cast<long long>(cases.size()));
    }

    return failures == 0 ? 0 : 1;
}
