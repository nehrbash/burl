pragma Singleton

import Burl.Services
import qs.components.misc
import qs.utils
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    property bool enabled: false
    property bool hibernateAfterSleep: true
    property date enabledSince: new Date()
    property bool _loaded: false

    onEnabledChanged: {
        if (enabled)
            enabledSince = new Date();
        save();
    }

    onHibernateAfterSleepChanged: save()

    function save(): void {
        if (_loaded)
            storage.setText(JSON.stringify({
                enabled: enabled,
                enabledSince: enabledSince.toISOString(),
                hibernateAfterSleep: hibernateAfterSleep
            }));
    }

    function execSessionAction(command: list<string>): bool {
        let action = command[0] ?? "";
        if ((action === "loginctl" || action === "systemctl") && command.length === 2)
            action = command[1];
        if (!hibernateAfterSleep && action.replace(/[-_]/g, "").toLowerCase() === "suspendthenhibernate") {
            SessionManager.suspend();
            return true;
        }
        return SessionManager.exec(command);
    }

    FileView {
        id: storage

        path: `${Paths.state}/idle-inhibitor.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.enabled = !!data.enabled;
                root.hibernateAfterSleep = data.hibernateAfterSleep ?? true;
                if (data.enabledSince)
                    root.enabledSince = new Date(data.enabledSince);
            } catch (e) {
                // Bad or missing file -- start disabled.
            }
            root._loaded = true;
        }
        onLoadFailed: {
            root._loaded = true;
        }
    }

    IdleInhibitor {
        enabled: root.enabled
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            mask: Region {}
        }
    }

    IpcHandler {
        function isEnabled(): bool {
            return root.enabled;
        }

        function toggle(): void {
            root.enabled = !root.enabled;
            if (root.enabled)
                Toaster.toast(qsTr("Keep awake enabled"), qsTr("Preventing sleep mode"), "coffee");
            else
                Toaster.toast(qsTr("Keep awake disabled"), qsTr("Normal power management"), "coffee");
        }

        function enable(): void {
            root.enabled = true;
        }

        function disable(): void {
            root.enabled = false;
        }

        target: "idleInhibitor"
    }
}
