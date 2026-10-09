pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Burl
import Burl.Config
import Burl.Internal
import qs.components.misc

Singleton {
    id: root

    readonly property var toplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors
    readonly property bool usingLua: Hyprland.usingLua

    readonly property HyprlandToplevel activeToplevel: {
        const t = Hyprland.activeToplevel;
        return t?.workspace?.name.startsWith("special:") || Hyprland.focusedWorkspace?.toplevels.values.length > 0 ? t : null;
    }
    readonly property HyprlandWorkspace focusedWorkspace: Hyprland.focusedWorkspace
    readonly property HyprlandMonitor focusedMonitor: Hyprland.focusedMonitor
    readonly property int activeWsId: focusedWorkspace?.id ?? 1

    readonly property HyprKeyboard keyboard: extras.devices.keyboards.find(kb => kb.main) ?? null
    readonly property bool capsLock: keyboard?.capsLock ?? false
    readonly property bool numLock: keyboard?.numLock ?? false
    readonly property string defaultKbLayout: keyboard?.layout.split(",")[0] ?? "??"
    readonly property string kbLayoutFull: keyboard?.activeKeymap ?? "Unknown"
    readonly property string kbLayout: kbMap.get(kbLayoutFull) ?? "??"
    readonly property var kbMap: new Map()

    readonly property alias extras: extras
    readonly property alias options: extras.options
    readonly property alias devices: extras.devices

    property bool hadKeyboard
    property string lastSpecialWorkspace: ""
    property string activeSubmap: ""

    // Focus history, newest first, as bare addresses. Hyprland's own client
    // list is creation-ordered, which is useless for a switcher — the window
    // you want back is almost always the one you just left.
    property list<string> mru: []

    onActiveToplevelChanged: {
        const addr = activeToplevel?.address;
        if (!addr)
            return;
        mru = [addr, ...mru.filter(a => a !== addr)].slice(0, 64);
    }

    signal configReloaded

    // Hyprland 0.55 lua config routes `hyprctl dispatch X` through
    // `hl.dispatch(X)`, requiring X to be a valid lua expression that
    // returns a dispatcher (e.g. `hl.dsp.exit()`).  Quickshell.Hyprland
    // still emits hyprlang-style strings ("workspace 1",
    // "togglespecialworkspace special", ...), so we translate here.
    //
    // ANY command missing from the switch below falls through to `return
    // request` and is then eval'd as lua, which ALWAYS fails — e.g.
    //   error: [string "return hl.dispatch(dpms off)"]:1: ')' expected near 'off'
    // That failure is silent unless you are reading quickshell.log, so a
    // dispatcher that is merely absent here looks like a feature that quietly
    // does nothing. Add the case here, not another ternary at the call site.
    //
    // Callers branching on `Hypr.usingLua` are vestigial: usingLua reads FALSE
    // on this host even though the compositor IS in lua mode, so the plain
    // branch always wins and this translation is what actually runs.
    function _luaDispatch(request: string): string {
        if (request.startsWith("hl."))
            return request;

        // Trailing "address:..." selector after a comma applies to most
        // window-targeting dispatchers.
        function splitSel(rest) {
            const i = rest.lastIndexOf(",address:");
            if (i < 0)
                return { args: rest, sel: null };
            return { args: rest.slice(0, i), sel: rest.slice(i + 1) };
        }
        function qstr(s) { return `"${s.replace(/"/g, '\\"')}"`; }
        function selField(sel) { return sel ? `, window = ${qstr(sel)}` : ""; }

        const sp  = request.indexOf(" ");
        const cmd = sp < 0 ? request : request.slice(0, sp);
        const rest = sp < 0 ? "" : request.slice(sp + 1);

        switch (cmd) {
        case "exit":
            return "hl.dsp.exit()";
        case "centerwindow":
            return `hl.dsp.window.center({${rest ? `window = ${qstr(rest)}` : ""}})`;
        case "workspace":
            return `hl.dsp.focus({ workspace = ${qstr(rest)} })`;
        case "focuswindow":
            return `hl.dsp.focus({ window = ${qstr(rest)} })`;
        case "dpms": {
            // `dpms off|on`. A trailing monitor argument is dropped rather than
            // guessed at: the lua binding's parameter name for it is unverified,
            // and no caller passes one.
            const state = rest.split(/\s+/, 1)[0];
            return `hl.dsp.dpms({ action = ${qstr(state === "off" ? "disable" : "enable")} })`;
        }
        case "togglespecialworkspace":
            return `hl.dsp.workspace.toggle_special(${qstr(rest)})`;
        case "moveworkspacetomonitor": {
            const [ws, mon] = rest.split(/\s+/, 2);
            return `hl.dsp.workspace.move({ workspace = ${qstr(ws)}, monitor = ${qstr(mon)} })`;
        }
        case "movetoworkspace": {
            const { args, sel } = splitSel(rest);
            return `hl.dsp.window.move({ workspace = ${qstr(args)}${selField(sel)} })`;
        }
        case "togglefloating": {
            const sel = rest.startsWith("address:") ? rest : null;
            return `hl.dsp.window.float({ action = "toggle"${selField(sel)} })`;
        }
        case "killwindow":
            return `hl.dsp.window.kill({ window = ${qstr(rest)} })`;
        case "pin":
            return `hl.dsp.window.pin({${rest ? ` window = ${qstr(rest)} ` : ""}})`;
        case "movewindowpixel":
        case "resizewindowpixel": {
            // exact X Y,address:0xHEX
            const { args, sel } = splitSel(rest);
            const m = args.match(/^(?:exact\s+)?(-?\d+)\s+(-?\d+)$/);
            if (!m)
                return request;
            const fn = cmd === "movewindowpixel" ? "move" : "resize";
            return `hl.dsp.window.${fn}({ x = ${m[1]}, y = ${m[2]}${selField(sel)} })`;
        }
        }
        return request;
    }

    function dispatch(request: string): void {
        Hyprland.dispatch(root._luaDispatch(request));
    }

    // Useful when two ops should land together (e.g. moveworkspacetomonitor
    // + workspace focus) to avoid per-click IPC pile-up.
    function batchDispatch(requests: list<string>): void {
        if (!requests || requests.length === 0)
            return;
        const msgs = requests.map(r => "dispatch " + root._luaDispatch(r));
        extras.batchMessage(msgs);
    }

    function cycleSpecialWorkspace(direction: string): void {
        const openSpecials = workspaces.values.filter(w => w.name.startsWith("special:") && w.toplevels.values.length > 0);

        if (openSpecials.length === 0)
            return;

        const activeSpecial = focusedMonitor.lastIpcObject.specialWorkspace.name ?? "";

        if (!activeSpecial) {
            if (lastSpecialWorkspace) {
                const workspace = workspaces.values.find(w => w.name === lastSpecialWorkspace);
                if (workspace && workspace.toplevels.values.length > 0) {
                    dispatch(usingLua ? `hl.dsp.focus({ workspace = "${lastSpecialWorkspace}" })` : `workspace ${lastSpecialWorkspace}`);
                    return;
                }
            }
            dispatch(usingLua ? `hl.dsp.focus({ workspace = "${openSpecials[0].name}" })` : `workspace ${openSpecials[0].name}`);
            return;
        }

        const currentIndex = openSpecials.findIndex(w => w.name === activeSpecial);
        let nextIndex = 0;

        if (currentIndex !== -1) {
            if (direction === "next")
                nextIndex = (currentIndex + 1) % openSpecials.length;
            else
                nextIndex = (currentIndex - 1 + openSpecials.length) % openSpecials.length;
        }

        dispatch(usingLua ? `hl.dsp.focus({ workspace = "${openSpecials[nextIndex].name}" })` : `workspace ${openSpecials[nextIndex].name}`);
    }

    function monitorNames(): list<string> {
        return monitors.values.map(e => e.name);
    }

    function monitorFor(screen: ShellScreen): HyprlandMonitor {
        return Hyprland.monitorFor(screen);
    }

    function reloadDynamicConfs(): void {
        if (usingLua) {
            extras.batchMessage(['eval hl.bind("Caps_Lock", hl.dsp.global("burl:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })', 'eval hl.bind("Num_Lock", hl.dsp.global("burl:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })']);
        } else {
            extras.batchMessage(["keyword bindlni ,Caps_Lock,global,burl:refreshDevices", "keyword bindlni ,Num_Lock,global,burl:refreshDevices"]);
        }
    }

    Component.onCompleted: reloadDynamicConfs()

    onCapsLockChanged: {
        if (!GlobalConfig.utilities.toasts.capsLockChanged)
            return;

        if (capsLock)
            Toaster.toast(qsTr("Caps lock enabled"), qsTr("Caps lock is currently enabled"), "keyboard_capslock_badge");
        else
            Toaster.toast(qsTr("Caps lock disabled"), qsTr("Caps lock is currently disabled"), "keyboard_capslock");
    }

    onNumLockChanged: {
        if (!GlobalConfig.utilities.toasts.numLockChanged)
            return;

        if (numLock)
            Toaster.toast(qsTr("Num lock enabled"), qsTr("Num lock is currently enabled"), "looks_one");
        else
            Toaster.toast(qsTr("Num lock disabled"), qsTr("Num lock is currently disabled"), "timer_1");
    }

    onKbLayoutFullChanged: {
        if (hadKeyboard && GlobalConfig.utilities.toasts.kbLayoutChanged)
            Toaster.toast(qsTr("Keyboard layout changed"), qsTr("Layout changed to: %1").arg(kbLayoutFull), "keyboard");

        hadKeyboard = !!keyboard;
    }

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.endsWith("v2"))
                return;

            // Quickshell core (connection.cpp HyprlandIpc::onEvent) already
            // updates workspace/monitor/toplevel state precisely on its own
            // for every event we care about (workspacev2, focusedmon, create
            // /destroyworkspacev2, openwindow, closewindow, movewindowv2,
            // monitorad/removed, fullscreen); only the few Hyprland-only
            // signals below need handling here.
            if (n === "activesubmap") {
                root.activeSubmap = event.data;
            } else if (n === "configreloaded") {
                root.configReloaded();
                root.reloadDynamicConfs();
            } else if (n === "activespecial") {
                // Not handled by core — monitor.lastIpcObject.specialWorkspace
                // is only refreshed via refreshMonitors.
                Hyprland.refreshMonitors();
            } else if (n === "fullscreen") {
                // Core tracks fullscreen on the WORKSPACE, which cannot tell
                // maximized (state 1) from fullscreen (state 2) — the bar only
                // hides for the latter, so it reads toplevel.lastIpcObject
                // instead, and that only moves on a refreshToplevels. Without
                // this the bar stays hidden after leaving fullscreen, its
                // exclusive zone still reserved, until some window opens.
                Hyprland.refreshToplevels();
            } else if (n === "openwindow") {
                // Core's openwindow handler only sets address/title/workspace
                // (updateInitial); toplevel.lastIpcObject (class, fullscreen, …)
                // stays empty until a refreshToplevels. One j/clients call per
                // window open keeps workspace app icons working.
                Hyprland.refreshToplevels();
            }
        }

        target: Hyprland
    }

    Connections {
        function onLastIpcObjectChanged(): void {
            const specialName = root.focusedMonitor.lastIpcObject.specialWorkspace.name;

            if (specialName && specialName.startsWith("special:")) {
                root.lastSpecialWorkspace = specialName;
            }
        }

        target: root.focusedMonitor
    }

    FileView {
        id: kbLayoutFile

        path: Quickshell.env("BURL_XKB_RULES_PATH") || "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: {
            const layoutMatch = text().match(/! layout\n([\s\S]*?)\n\n/);
            if (layoutMatch) {
                const lines = layoutMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-z]{2,})\s+([a-zA-Z() ]+)$/);
                    if (match)
                        root.kbMap.set(match[2], match[1]);
                }
            }

            const variantMatch = text().match(/! variant\n([\s\S]*?)\n\n/);
            if (variantMatch) {
                const lines = variantMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-zA-Z0-9_-]+)\s+([a-z]{2,}): (.+)$/);
                    if (match)
                        root.kbMap.set(match[3], match[2]);
                }
            }
        }
    }

    IpcHandler {
        function refreshDevices(): void {
            extras.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return root.workspaces.values.filter(w => w.name.startsWith("special:") && w.toplevels.values.length > 0).map(w => w.name).join("\n");
        }

        target: "hypr"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "refreshDevices"
        description: "Reload devices"
        onPressed: extras.refreshDevices()
        onReleased: extras.refreshDevices()
    }

    HyprExtras {
        id: extras

        usingLua: Hyprland.usingLua
    }
}
