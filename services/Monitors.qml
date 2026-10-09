pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl
import qs.services

// Generated monitor rules must remain writable beside the compositor configuration.
Singleton {
    id: root

    // Every monitor including DISABLED ones, from `hyprctl monitors all -j`.
    // Quickshell's Hypr.monitors lists only ACTIVE monitors, so a monitor the
    // user disables vanishes from the model and can no longer be re-enabled
    // from the UI.  This is the source of truth for the settings pane.
    property var all: []

    function refresh(): void {
        allProc.running = true;
    }

    Process {
        id: allProc

        command: ["hyprctl", "monitors", "all", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.all = JSON.parse(text);
                } catch (e) {
                    // leave `all` unchanged on a malformed read
                }
            }
        }
    }

    // Per-host: no cross-machine clobbering.
    readonly property string luaPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hypr/monitors-generated.lua"

    property bool persisting: false
    signal persisted(bool success, string message)

    // Stable per-panel identity: `desc:<description>` so a rule follows the
    // physical monitor across ports/docks.  Truncate at the first comma
    // (Hyprland prefix-matches descriptions, and a comma would break the
    // comma-delimited monitor rule).  Fall back to the output name.
    function descKey(description: string, name: string): string {
        if (!description)
            return name;
        const d = description.split(",")[0].trim();
        return d ? "desc:" + d : name;
    }

    // Snapshot a raw `hyprctl monitors all -j` object into a plain editable
    // config.  Disabled monitors still carry their last-known mode/scale/etc,
    // so a disabled monitor's card shows sensible values.
    function snapshot(o): var {
        o = o ?? ({});
        return {
            output: root.descKey(o.description ?? "", o.name ?? ""),
            name: o.name ?? "",
            description: o.description ?? "",
            disabled: o.disabled ?? false,
            width: o.width ?? 0,
            height: o.height ?? 0,
            refresh: Math.round(o.refreshRate ?? 60),
            x: o.x ?? 0,
            y: o.y ?? 0,
            scale: o.scale ?? 1,
            transform: o.transform ?? 0,
            vrr: (o.vrr ?? false) ? 1 : 0,
            bitdepth: (o.currentFormat ?? "").indexOf("2101010") >= 0 ? 10 : 8,
            availableModes: o.availableModes ?? []
        };
    }

    // "preferred" covers a monitor with no known mode (e.g. one that was
    // disabled before Hyprland could probe it) — a 0x0 mode is a hard reject.
    function modeString(cfg): string {
        if (!(cfg.width > 0) || !(cfg.height > 0))
            return "preferred";
        return `${cfg.width}x${cfg.height}@${cfg.refresh}`;
    }

    function positionString(cfg): string {
        return `${cfg.x}x${cfg.y}`;
    }

    function _scaleStr(s: real): string {
        const r = Math.round(s * 1e6) / 1e6;
        return Number.isInteger(r) ? r.toFixed(1) : String(r);
    }

    // Build the `hl.monitor({...})` lua expression for one config. Matches the
    // line format hypr-monitor-write persists, so live and saved state agree.
    function monitorExpr(cfg): string {
        if (cfg.disabled)
            return `hl.monitor({ output = "${cfg.output}", disabled = true })`;
        let s = `hl.monitor({ output = "${cfg.output}", mode = "${modeString(cfg)}", position = "${positionString(cfg)}", scale = ${_scaleStr(cfg.scale)}`;
        if (cfg.transform)
            s += `, transform = ${cfg.transform}`;
        s += `, vrr = ${cfg.vrr}`;
        if (cfg.bitdepth === 10)
            s += ", bitdepth = 10";
        return s + " })";
    }

    // Hyprland 0.55's lua config rejects `hyprctl keyword monitor ...`
    // ("keyword can't work with non-legacy parsers. Use eval."), so we apply
    // the rule by eval'ing the equivalent `hl.monitor(...)` call instead.
    //
    // NOTE: eval can disable an output and change mode/scale/position live, but
    // it CANNOT re-enable an already-disabled output (Hyprland doesn't re-probe
    // it).  Re-enabling — and reverting an accidental disable — therefore goes
    // through persistAndReload(), since `hyprctl reload` re-runs the catch-all
    // monitor rule and brings the output back.
    function applyLive(cfg): void {
        Hypr.extras.message("eval " + root.monitorExpr(cfg));
        root.resyncVideoWallpaper();
    }

    // A live output change invalidates the video wallpaper's layer surfaces
    // (see Wallpapers.restartVideoDaemon), so rebuild them.
    // Debounced: the display pane applies one monitor at a time.
    function resyncVideoWallpaper(): void {
        videoResync.restart();
    }

    Timer {
        id: videoResync

        interval: 1500
        onTriggered: Wallpapers.restartVideoDaemon()
    }

    property bool _reloadAfter: false

    // `hyprctl reload` re-reads the generated lua, so it both re-enables
    // disabled outputs and resets live eval edits to exactly `configs` — used
    // for enabling a monitor and for revert.
    function persistAndReload(configs): void {
        root._reloadAfter = true;
        root.persist(configs);
    }

    function persist(configs): void {
        if (root.persisting)
            return;
        // Strip the QML-only availableModes field before serialising.
        const clean = configs.map(c => ({
                    output: c.output,
                    disabled: c.disabled,
                    width: c.width,
                    height: c.height,
                    refresh: c.refresh,
                    x: c.x,
                    y: c.y,
                    scale: c.scale,
                    transform: c.transform,
                    vrr: c.vrr,
                    bitdepth: c.bitdepth
                }));
        writer.command = ["hypr-monitor-write", root.luaPath, JSON.stringify(clean)];
        root.persisting = true;
        writer.running = true;
    }

    Process {
        id: writer

        stderr: StdioCollector {
            id: writerErr
        }

        onExited: code => {
            root.persisting = false;
            if (code === 0) {
                if (root._reloadAfter) {
                    root._reloadAfter = false;
                    reloader.running = true;
                } else {
                    Toaster.toast(qsTr("Monitors saved"), qsTr("Persisted for next reload"), "save");
                }
                root.persisted(true, "");
            } else {
                root._reloadAfter = false;
                const err = writerErr.text || qsTr("exit %1").arg(code);
                Toaster.toast(qsTr("Save failed"), err, "error");
                root.persisted(false, err);
            }
        }
    }

    Process {
        id: reloader

        command: ["hyprctl", "reload"]
        onExited: {
            root.refresh();
            root.resyncVideoWallpaper();
        }
    }
}
