pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl.Config
import Burl.Internal

Singleton {
    id: root

    property int refCount: 0
    readonly property bool sampling: refCount > 0

    onSamplingChanged: resetSampling()

    // Current speeds in bytes per second
    readonly property real downloadSpeed: _downloadSpeed
    readonly property real uploadSpeed: _uploadSpeed

    // Total bytes transferred since tracking started
    readonly property real downloadTotal: _downloadTotal
    readonly property real uploadTotal: _uploadTotal

    // History buffers for sparkline
    readonly property alias downloadBuffer: downloadHistory
    readonly property alias uploadBuffer: uploadHistory
    readonly property int historyLength: 30

    property real _downloadSpeed: 0
    property real _uploadSpeed: 0
    property real _downloadTotal: 0
    property real _uploadTotal: 0

    property var _previousCounters: null
    property real _prevTimestamp: 0

    function resetSampling(): void {
        root._previousCounters = null;
        root._downloadSpeed = 0;
        root._uploadSpeed = 0;
    }

    function formatBytes(bytes: real): var {
        if (bytes < 0 || isNaN(bytes) || !isFinite(bytes)) {
            return {
                value: 0,
                unit: "B/s"
            };
        }

        if (bytes < 1024) {
            return {
                value: bytes,
                unit: "B/s"
            };
        } else if (bytes < 1024 * 1024) {
            return {
                value: bytes / 1024,
                unit: "KB/s"
            };
        } else if (bytes < 1024 * 1024 * 1024) {
            return {
                value: bytes / (1024 * 1024),
                unit: "MB/s"
            };
        } else {
            return {
                value: bytes / (1024 * 1024 * 1024),
                unit: "GB/s"
            };
        }
    }

    function formatBytesTotal(bytes: real): var {
        if (bytes < 0 || isNaN(bytes) || !isFinite(bytes)) {
            return {
                value: 0,
                unit: "B"
            };
        }

        if (bytes < 1024) {
            return {
                value: bytes,
                unit: "B"
            };
        } else if (bytes < 1024 * 1024) {
            return {
                value: bytes / 1024,
                unit: "KB"
            };
        } else if (bytes < 1024 * 1024 * 1024) {
            return {
                value: bytes / (1024 * 1024),
                unit: "MB"
            };
        } else {
            return {
                value: bytes / (1024 * 1024 * 1024),
                unit: "GB"
            };
        }
    }

    function parseNetDev(content: string): var {
        const lines = content.split("\n");
        const counters = Object.create(null);

        for (let i = 2; i < lines.length; i++) {
            const line = lines[i].trim();
            const colon = line.indexOf(":");
            if (colon < 0)
                continue;

            const iface = line.slice(0, colon).trim();
            if (!iface || iface === "lo")
                continue;

            const parts = line.slice(colon + 1).trim().split(/\s+/);
            if (parts.length < 16)
                continue;

            const rx = Number(parts[0]);
            const tx = Number(parts[8]);
            if (isFinite(rx) && isFinite(tx) && rx >= 0 && tx >= 0)
                counters[iface] = { rx, tx };
        }

        return counters;
    }

    CircularBuffer {
        id: downloadHistory

        capacity: root.historyLength + 1
    }

    CircularBuffer {
        id: uploadHistory

        capacity: root.historyLength + 1
    }

    FileView {
        id: netDevFile

        path: "/proc/net/dev"
        // reload() is async: sampling in onLoaded rather than after the call
        // is what keeps each tick from measuring the previous tick's bytes.
        onLoaded: root.sample(text())
    }

    Timer {
        interval: GlobalConfig.dashboard.resourceUpdateInterval
        running: root.sampling
        repeat: true
        triggeredOnStart: true

        onTriggered: netDevFile.reload()
    }

    function sample(content: string): void {
        if (!root.sampling || !content)
            return;

        const counters = root.parseNetDev(content);
        const now = Date.now();
        if (root._previousCounters === null) {
            root._previousCounters = counters;
            root._prevTimestamp = now;
            return;
        }

        const seconds = (now - root._prevTimestamp) / 1000;
        if (seconds <= 0)
            return;

        let received = 0;
        let sent = 0;
        for (const iface of Object.keys(counters)) {
            const previous = root._previousCounters[iface];
            if (!previous)
                continue;
            // New interfaces and reset counters carry no observed traffic delta.
            received += Math.max(0, counters[iface].rx - previous.rx);
            sent += Math.max(0, counters[iface].tx - previous.tx);
        }

        root._downloadSpeed = received / seconds;
        root._uploadSpeed = sent / seconds;
        root._downloadTotal += received;
        root._uploadTotal += sent;
        downloadHistory.push(root._downloadSpeed);
        uploadHistory.push(root._uploadSpeed);
        root._previousCounters = counters;
        root._prevTimestamp = now;
    }
}
