#pragma once

#include <qjsonarray.h>
#include <qstring.h>

namespace burl {

// Runs `hyprctl` with the given arguments and returns stdout. Throws Error
// naming `action` when it fails or takes longer than five seconds.
QString hyprctl(const QStringList& arguments, const QString& action);

// Enabled monitors as reported by `hyprctl -j monitors`.
QJsonArray hyprMonitors();

} // namespace burl
