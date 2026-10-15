#pragma once

#include <qstring.h>

namespace burl {

// Best effort: a missing notification daemon must not fail the command.
void notifyCritical(const QString& summary, const QString& body);

} // namespace burl
