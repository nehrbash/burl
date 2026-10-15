#pragma once

#include <qstringlist.h>

namespace burl {

// Runs the `burl` command line (arguments without the program name) and
// returns the process exit status.
int runCli(const QStringList& arguments);

} // namespace burl
