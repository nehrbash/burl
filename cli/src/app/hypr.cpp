#include "hypr.hpp"

#include "util.hpp"

#include <qjsondocument.h>

using Qt::StringLiterals::operator""_s;

namespace burl {

QString hyprctl(const QStringList& arguments, const QString& action) {
    ProcessResult result;
    try {
        result = runProcess(u"hyprctl"_s, arguments, 5000);
    } catch (const Error& error) {
        throw Error(u"Hyprland %1 failed: %2"_s.arg(action, QString::fromUtf8(error.what())));
    }

    if (result.timedOut) {
        throw Error(u"Hyprland %1 failed: timed out"_s.arg(action));
    }
    if (result.exitCode != 0) {
        auto detail = QString::fromUtf8(result.err).trimmed();
        if (detail.isEmpty()) {
            detail = QString::fromUtf8(result.out).trimmed();
        }
        if (detail.isEmpty()) {
            detail = u"exit status %1"_s.arg(result.exitCode);
        }
        throw Error(u"Hyprland %1 failed: %2"_s.arg(action, detail));
    }
    return QString::fromUtf8(result.out);
}

QJsonArray hyprMonitors() {
    const auto text = hyprctl({u"-j"_s, u"monitors"_s}, u"monitor query"_s);
    const auto document = QJsonDocument::fromJson(text.toUtf8());
    if (!document.isArray()) {
        throw Error(u"Hyprland monitor query did not return a list"_s);
    }
    return document.array();
}

} // namespace burl
