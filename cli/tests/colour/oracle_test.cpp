#include "colour/colour.hpp"
#include "hct.hpp"
#include "resample.hpp"

#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <stdexcept>
#include <vector>

namespace {

using namespace burl::colour;

int failures = 0;

void fail(const QString& where, const QString& what, const QString& expected, const QString& got) {
    ++failures;
    std::fprintf(stderr, "%s: %s: expected %s, got %s\n", qPrintable(where), qPrintable(what), qPrintable(expected),
        qPrintable(got));
}

QByteArray read(const char* name) {
    QFile file(QString::fromLatin1(BURL_ORACLE_DIR) + "/" + QString::fromLatin1(name));
    if (!file.open(QIODevice::ReadOnly)) {
        std::fprintf(stderr, "cannot open %s\n", qPrintable(file.fileName()));
        std::exit(2);
    }

    return file.readAll();
}

// QJsonObject sorts its keys, but the colour order is part of the contract: read the key order of every `colours`
// object straight from the text.
std::vector<QStringList> colourKeyOrders(const QByteArray& text) {
    std::vector<QStringList> orders;
    const QByteArray marker = "\"colours\": {";
    qsizetype at = 0;
    while ((at = text.indexOf(marker, at)) >= 0) {
        at += marker.size();
        QStringList keys;
        while (true) {
            const qsizetype keyStart = text.indexOf('"', at);
            const qsizetype close = text.indexOf('}', at);
            if (keyStart < 0 || (close >= 0 && close < keyStart)) {
                break;
            }

            const qsizetype keyEnd = text.indexOf('"', keyStart + 1);
            keys.append(QString::fromUtf8(text.mid(keyStart + 1, keyEnd - keyStart - 1)));
            const qsizetype valueStart = text.indexOf('"', text.indexOf(':', keyEnd));
            at = text.indexOf('"', valueStart + 1) + 1;
        }

        orders.push_back(keys);
    }

    return orders;
}

std::uint32_t parseHex(const QString& text) {
    return text.toUInt(nullptr, 16);
}

QString hex8(std::uint32_t argb) {
    return QStringLiteral("%1").arg(argb, 8, 16, QLatin1Char('0')).toUpper();
}

int checkSchemes() {
    const QByteArray text = read("schemes.json");
    const QJsonArray cases = QJsonDocument::fromJson(text).array();
    const std::vector<QStringList> orders = colourKeyOrders(text);
    std::size_t order = 0;
    int passed = 0;
    for (const QJsonValue& value : cases) {
        const QJsonObject object = value.toObject();
        const QStringList keyOrder = object.contains("colours") ? orders.at(order++) : QStringList();
        const QString where = object["seed"].toString() + " " + object["variant"].toString() + " " +
            object["mode"].toString() + " " + object["flavour"].toString();
        const Selection selection{ object["variant"].toString().toStdString(),
            object["flavour"].toString().toStdString(), object["mode"].toString().toStdString() };
        const int before = failures;

        try {
            const Colours colours = generate(selection, parseHex(object["seed"].toString()));
            if (object.contains("error")) {
                fail(where, "result", object["error"].toString(), "no exception");
            } else {
                const QJsonObject expected = object["colours"].toObject();
                if (static_cast<qsizetype>(colours.size()) != expected.size()) {
                    fail(where, "colour count", QString::number(expected.size()), QString::number(colours.size()));
                }

                for (std::size_t i = 0; i < colours.size(); ++i) {
                    const QString key = QString::fromStdString(colours[i].first);
                    const QString got = QString::fromStdString(colours[i].second);
                    if (static_cast<qsizetype>(i) < keyOrder.size() && keyOrder[static_cast<qsizetype>(i)] != key) {
                        fail(where, QStringLiteral("order[%1]").arg(i), keyOrder[static_cast<qsizetype>(i)], key);
                    }

                    if (!expected.contains(key)) {
                        fail(where, key, "absent", got);
                    } else if (expected[key].toString() != got) {
                        fail(where, key, expected[key].toString(), got);
                    }
                }
            }
        } catch (const std::domain_error&) {
            if (!object.contains("error")) {
                fail(where, "result", "colours", "std::domain_error");
            }
        } catch (const std::exception& error) {
            fail(where, "result", object.contains("error") ? "std::domain_error" : "colours", error.what());
        }

        if (failures == before) {
            ++passed;
        }
    }

    std::printf("schemes: %d/%lld passed\n", passed, static_cast<long long>(cases.size()));
    return passed;
}

int checkImages() {
    const QJsonArray cases = QJsonDocument::fromJson(read("images.json")).array();
    int passed = 0;
    for (const QJsonValue& value : cases) {
        const QJsonObject object = value.toObject();
        const QString name = object["image"].toString();
        const std::string path = (QString::fromLatin1(BURL_ORACLE_DIR) + "/images/" + name).toStdString();
        const int before = failures;

        try {
            const QString score = hex8(scoreImage(path));
            if (score != object["score"].toString()) {
                fail(name, "score", object["score"].toString(), score);
            }

            const Image image = loadImage(path);
            const double colourful = colourfulness(image);
            const double expected = object["colourfulness"].toDouble();
            if (std::abs(colourful - expected) > 1e-12 * std::max(1.0, std::abs(expected))) {
                fail(name, "colourfulness", QString::number(expected, 'g', 17), QString::number(colourful, 'g', 17));
            }

            const QString variant = QString::fromStdString(variantFor(image));
            if (variant != object["variant"].toString()) {
                fail(name, "variant", object["variant"].toString(), variant);
            }

            std::vector<std::uint8_t> rgb;
            for (const std::uint32_t argb : image.argb) {
                rgb.push_back(static_cast<std::uint8_t>((argb >> 16) & 0xFF));
                rgb.push_back(static_cast<std::uint8_t>((argb >> 8) & 0xFF));
                rgb.push_back(static_cast<std::uint8_t>(argb & 0xFF));
            }

            const auto pixel = lanczosMeanPixel(rgb, image.width, image.height);
            const QJsonArray expectedPixel = object["meanPixel"].toArray();
            for (int channel = 0; channel < 3; ++channel) {
                if (pixel[static_cast<std::size_t>(channel)] != expectedPixel[channel].toInt()) {
                    fail(name, QStringLiteral("meanPixel[%1]").arg(channel),
                        QString::number(expectedPixel[channel].toInt()),
                        QString::number(pixel[static_cast<std::size_t>(channel)]));
                }
            }

            const double tone = Hct::fromInt(argbFromRgb(pixel[0], pixel[1], pixel[2])).tone();
            if (std::abs(tone - object["tone"].toDouble()) > 1e-12) {
                fail(name, "tone", QString::number(object["tone"].toDouble(), 'g', 17), QString::number(tone, 'g', 17));
            }

            const QString mode = QString::fromStdString(modeFor(image));
            if (mode != object["mode"].toString()) {
                fail(name, "mode", object["mode"].toString(), mode);
            }
        } catch (const std::exception& error) {
            fail(name, "result", "image values", error.what());
        }

        if (failures == before) {
            ++passed;
        }
    }

    std::printf("images: %d/%lld passed\n", passed, static_cast<long long>(cases.size()));
    return passed;
}

} // namespace

int main() {
    checkSchemes();
    checkImages();
    if (failures > 0) {
        std::fprintf(stderr, "%d mismatches\n", failures);
        return 1;
    }

    return 0;
}
