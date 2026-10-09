#pragma once

#include "configobject.hpp"

#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

namespace burl::config {

using Qt::StringLiterals::operator""_s;

class GuixConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_GLOBAL_PROPERTY(QVariantList, actions,
        {
            vmap({
                { u"id"_s, u"pull"_s },
                { u"label"_s, u"Pull channels"_s },
                { u"icon"_s, u"cloud_download"_s },
                { u"command"_s, QStringList{ u"guix"_s, u"pull"_s } },
            }),
        })

    // Garbage collection does NOT go through `actions': it is the one operation
    // that really is a guix-daemon call (collect-garbage over the worker
    // protocol), so the backend performs it directly instead of spawning a CLI.
    CONFIG_GLOBAL_PROPERTY(bool, confirmGc, true)
    // Upstream comparison costs a git ls-remote + fetch per channel (~13s for
    // two), so the page shows cached commits immediately and only checks
    // upstream when asked, or once per this many minutes. 0 disables polling.
    CONFIG_GLOBAL_PROPERTY(int, upstreamCheckMinutes, 60)

public:
    explicit GuixConfig(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

} // namespace burl::config
