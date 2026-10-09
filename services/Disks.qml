pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Removable media tracker. udiskie automounts USB drives under
// /run/media/<user>/ (see home/services/udiskie.scm); we enumerate those
// via lsblk and refresh on udisks events. Exposes the mounted list to the
// bar status icon + popout, and an eject() that unmounts and powers off
// the backing drive.
Singleton {
    id: root

    // Each entry: { name, path, label, fstype, size, mountpoint, drive }
    property var mounted: []
    readonly property bool busy: ejectProc.running

    function refresh(): void {
        lsblkProc.running = false;
        lsblkProc.running = true;
    }

    function open(item: var): void {
        if (item?.mountpoint)
            Quickshell.execDetached(["xdg-open", item.mountpoint]);
    }

    function eject(item: var): void {
        if (!item || busy)
            return;
        ejectProc.exec(["sh", "-c", `udisksctl unmount -b ${item.path} && udisksctl power-off -b ${item.drive}`]);
    }

    Component.onCompleted: root.refresh()

    Process {
        id: lsblkProc

        command: ["lsblk", "-J", "-o", "NAME,PATH,LABEL,FSTYPE,SIZE,MOUNTPOINT,TYPE"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                try {
                    const data = JSON.parse(text);
                    const walk = (nodes, drive) => {
                        for (const n of nodes ?? []) {
                            const mp = n.mountpoint;
                            // udisks mounts removable media here; this filter
                            // excludes /, /boot, /mnt/storage and other fstab mounts.
                            if (mp && mp.startsWith("/run/media/"))
                                out.push({
                                    name: n.name,
                                    path: n.path,
                                    label: n.label || n.name,
                                    fstype: n.fstype || "",
                                    size: n.size || "",
                                    mountpoint: mp,
                                    drive: drive || n.path
                                });
                            if (n.children)
                                walk(n.children, n.path);
                        }
                    };
                    walk(data.blockdevices, "");
                } catch (e) {
                    console.warn("Disks: failed to parse lsblk:", e);
                }
                root.mounted = out;
            }
        }
    }

    Process {
        id: ejectProc

        onExited: root.refresh() // qmllint disable signal-handler-parameters
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.warn("Disks: eject:", text.trim());
            }
        }
    }

    // React to udisks device events (mount/unmount/insert/remove).
    Process {
        id: monitorProc

        running: true
        command: ["udisksctl", "monitor"]
        stdout: SplitParser {
            onRead: refreshTimer.restart()
        }
        // Respawn on exit and re-enumerate (same pattern as Nmcli's `nmcli
        // monitor`) — a dead monitor otherwise misses events for good.
        // Replaces a 5s lsblk poll that forked ~17k processes/day for no change.
        onExited: monitorRestartTimer.start() // qmllint disable signal-handler-parameters
    }

    Timer {
        id: monitorRestartTimer

        interval: 2000
        onTriggered: {
            monitorProc.running = true;
            root.refresh();
        }
    }

    Timer {
        id: refreshTimer

        interval: 400
        onTriggered: root.refresh()
    }
}
