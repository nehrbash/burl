// Window resizer: listens for window open/title events on the Hyprland IPC
// stream and applies size/position/float rules. Pure QML — it replaced an
// out-of-process Python daemon, which is why there is no uv runtime dep.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

Scope {
    id: root

    // Hardcoded defaults — match the upstream Python defaults verbatim.
    // Schema: { name, matchType, width, height, actions[] }
    //   matchType: titleContains | titleExact | titleRegex | initialTitle
    //   actions:   float | center | pip
    //   width/height: passed verbatim to Hyprland (accepts "20%" or pixels)
    readonly property var rules: [
        { name: "(Bitwarden", matchType: "titleContains", width: "20%", height: "54%", actions: ["float", "center"] },
        { name: "oauth", matchType: "titleContains", width: "30%", height: "60%", actions: ["float", "center"] },
        { name: "^[Pp]icture(-| )in(-| )[Pp]icture$", matchType: "titleRegex", width: "", height: "", actions: ["pip"] }
    ]

    // window-id -> last-applied unix-ms; 1s rate limit per window.
    property var lastApplied: ({})

    function rateLimited(id: string): bool {
        const now = Date.now();
        if (now - (lastApplied[id] ?? 0) < 1000)
            return true;
        lastApplied[id] = now;
        return false;
    }

    function findRule(title: string, initialTitle: string): var {
        for (const r of rules) {
            if (r.matchType === "initialTitle" && initialTitle === r.name)
                return r;
            if (r.matchType === "titleContains" && title.includes(r.name))
                return r;
            if (r.matchType === "titleExact" && title === r.name)
                return r;
            if (r.matchType === "titleRegex") {
                try {
                    if (new RegExp(r.name).test(title))
                        return r;
                } catch (e) {}
            }
        }
        return null;
    }

    function findClient(address: string): var {
        for (const t of Hypr.toplevels.values) {
            const obj = t.lastIpcObject;
            if (obj && obj.address === address)
                return obj;
        }
        return null;
    }

    function applyPip(address: string, client: var): void {
        if (!client?.floating)
            return;
        const wsName = client.workspace?.name;
        const ws = Hypr.workspaces.values.find(w => w.lastIpcObject?.name === wsName)?.lastIpcObject;
        if (!ws)
            return;
        const mon = Hypr.monitors.values.find(m => m.lastIpcObject?.id === ws.monitorID)?.lastIpcObject;
        if (!mon)
            return;

        const [w, h] = client.size ?? [0, 0];
        if (!w || !h)
            return;

        const mw = mon.width / mon.scale;
        const mh = mon.height / mon.scale;

        const scale = mh / 4 / h;
        const sw = Math.max(Math.floor(w * scale), 200);
        const sh = Math.max(Math.floor(h * scale), 150);
        const off = Math.min(mw, mh) * 0.03;
        const x = Math.floor(mon.x + mw - sw - off);
        const y = Math.floor(mon.y + mh - sh - off);

        Hypr.dispatch(`resizewindowpixel exact ${sw} ${sh},address:${address}`);
        Hypr.dispatch(`movewindowpixel exact ${x} ${y},address:${address}`);
    }

    function applyRule(address: string, rule: var): void {
        const client = findClient(address);
        if (!client)
            return;

        if (rule.actions.includes("pip")) {
            applyPip(address, client);
            return;
        }

        if (rule.actions.includes("float") && !client.floating)
            Hypr.dispatch(`togglefloating address:${address}`);

        if (rule.width && rule.height)
            Hypr.dispatch(`resizewindowpixel exact ${rule.width} ${rule.height},address:${address}`);

        if (rule.actions.includes("center"))
            Hypr.dispatch("centerwindow");
    }

    function handle(address: string, title: string, initialTitle: string): void {
        const rule = findRule(title, initialTitle);
        if (!rule)
            return;
        if (rateLimited(address))
            return;
        applyRule(address, rule);
    }

    IpcHandler {
        // `pip()` puts the active floating window into picture-in-picture
        // (bottom-right corner, scaled). Mirrors `burl resizer pip`.
        function pip(): void {
            const active = Hypr.activeToplevel?.lastIpcObject;
            if (!active || !active.address)
                return;
            if (!active.floating)
                return;
            root.applyPip(active.address, active);
        }

        target: "resizer"
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            const d = event.data;
            if (n === "windowtitle" || n === "windowtitlev2") {
                // v1: "<id>"  v2: "<id>,<title>"
                const id = d.split(",")[0];
                if (!id)
                    return;
                const address = `0x${id}`;
                // Wait a tick so refreshToplevels in Hypr.qml can update.
                Qt.callLater(() => {
                    const c = root.findClient(address);
                    if (c)
                        root.handle(address, c.title ?? "", c.initialTitle ?? "");
                });
            } else if (n === "openwindow") {
                // "<id>,<workspace>,<class>,<title>"
                const parts = d.split(",");
                if (parts.length < 4)
                    return;
                const id = parts[0];
                const title = parts.slice(3).join(",");
                Qt.callLater(() => {
                    root.handle(`0x${id}`, title, title);
                });
            }
        }
    }
}
