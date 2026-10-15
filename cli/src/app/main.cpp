#include "cli.hpp"

#include <qcoreapplication.h>
#include <qimagereader.h>

int main(int argc, char* argv[]) {
    const QCoreApplication app(argc, argv);
    // Wallpapers can exceed Qt's default 256 MB decode limit.
    QImageReader::setAllocationLimit(0);
    auto arguments = QCoreApplication::arguments();
    arguments.removeFirst();
    return burl::runCli(arguments);
}
