//@ pragma DropExpensiveFonts

// Environment for this shell is NOT set here. It is declared on the Shepherd
// service that launches us, in desktop/burl.scm — one place, applied for real,
// reconfigured with the rest of the home environment.
//
// `DropExpensiveFonts` stays as a pragma (not env) because this quickshell
// build only recognizes a fixed pragma set (see src/launch/launch.cpp); no
// `DefaultEnv` pragma exists, so setting env vars via pragma here is a no-op.

import "modules"
import "modules/drawers"
import "modules/background"
import "modules/areapicker"
import "modules/lock"
import "modules/cheatsheet"
import "modules/switcher"
import "modules/tasknudge"
import QtQuick
import Quickshell
import qs.services

ShellRoot {
    id: root

    settings.watchFiles: true

    Binding {
        target: ShellState
        property: "shellRoot"
        value: root
    }

    GSFLoader {}

    Background {}
    Drawers {}
    AreaPicker {}
    Lock {
        id: lock
    }
    TaskNudge {}
    Switcher {}
    Cheatsheet {}

    ConfigToasts {}
    Shortcuts {}
    BatteryMonitor {}
    Resizer {}
    IdleMonitors {
        lock: lock
    }
}
