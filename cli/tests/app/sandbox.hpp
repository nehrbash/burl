#pragma once

#include <qdir.h>
#include <qtemporarydir.h>

// XDG directories under a temporary root, with Hyprland unreachable.
struct Sandbox {
    QTemporaryDir root;
    QString config;
    QString data;
    QString state;
    QString cache;

    Sandbox()
        : config(root.filePath(QStringLiteral("config")))
        , data(root.filePath(QStringLiteral("data")))
        , state(root.filePath(QStringLiteral("state")))
        , cache(root.filePath(QStringLiteral("cache"))) {
        for (const auto& dir : {config, data, state, cache}) {
            QDir().mkpath(dir);
        }
    }

    void exportEnvironment() const {
        qputenv("XDG_CONFIG_HOME", config.toLocal8Bit());
        qputenv("XDG_DATA_HOME", data.toLocal8Bit());
        qputenv("XDG_STATE_HOME", state.toLocal8Bit());
        qputenv("XDG_CACHE_HOME", cache.toLocal8Bit());
        qputenv("BURL_CLI_DATA_DIR", BURL_TEST_DATA_DIR);
        qunsetenv("HYPRLAND_INSTANCE_SIGNATURE");
        qunsetenv("QS_WALLPAPERS_DIR");
        qunsetenv("BURL_WALLPAPERS_DIR");
    }
};
