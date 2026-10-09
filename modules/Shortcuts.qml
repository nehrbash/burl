import QtQuick
import Quickshell
import Quickshell.Io
import Burl
import Burl.Config
import qs.components.misc
import qs.services
import qs.modules.nexus

Scope {
    id: root

    property bool launcherInterrupted
    readonly property bool hasFullscreen: Hypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject?.fullscreen > 1) ?? false
    // The `drawers` IPC contract — keep in sync with components/ScreenState.qml.
    readonly property list<string> drawerNames: ["bar", "osd", "launcher", "dashboard", "utilities", "sidebar"]

    // Force-mount the FocusMode singleton so its IpcHandler ("focusMode")
    // is live from startup — this scope is always instantiated (shell.qml
    // root). Same lazy-load trap as idleInhibitor (see hypr/actions.lua).
    readonly property bool focusModeActive: FocusMode.enabled

    // "dashboard,media*" — comma-joined open set with the emphasised id
    // suffixed "*". Shared by the dashboard IPC's open/fold/emphasise/
    // openSections handlers so the wire format only lives in one place.
    function formatOpenSections(screenState: var): string {
        const open = screenState.dashboardOpenSections ?? [];
        const emphasis = screenState.dashboardSection;
        return open.map(id => id === emphasis ? `${id}*` : id).join(",");
    }

    function toggleRoom(screenState: var, room: string): void {
        if (GlobalConfig.dashboard.navStyle === "living")
            screenState.toggleWorldRoom(room);
        else
            screenState[room] = !screenState[room];
    }

    // Session controls need a bare tree, with no book covering the roots.
    function openSession(): void {
        if (root.hasFullscreen)
            return;
        const screenState = ShellState.forActive();
        root.toggleRoom(screenState, "dashboard");
        if (!screenState.dashboard)
            return;
        screenState.dashboardOpenedByKey = true;
        screenState.foldAllDashboardSections();
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "nexus"
        description: "Open nexus"
        onPressed: WindowFactory.create()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "showall"
        description: "Toggle launcher, dashboard and osd"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const v = ShellState.forActive();
            // navStyle "living" drops the dashboard from this bundle: it is
            // bottom-centre full-screen, same as the launcher, so growing it
            // behind an open launcher makes no sense.
            const includeDashboard = GlobalConfig.dashboard.navStyle !== "living";
            const anyOpen = v.launcher || (includeDashboard && v.dashboard) || v.osd || v.utilities;
            const next = !anyOpen;
            v.launcher = next;
            if (includeDashboard)
                v.dashboard = next;
            v.osd = next;
            v.utilities = next;
            if (includeDashboard && v.dashboard)
                v.dashboardOpenedByKey = true;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "dashboard"
        description: "Toggle dashboard"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            root.toggleRoom(screenState, "dashboard");
            // Opened on purpose, so it may take keyboard focus (a merely
            // hover-opened dashboard must not steal keystrokes).
            if (screenState.dashboard)
                screenState.dashboardOpenedByKey = true;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "session"
        description: "Open the dashboard on the world tree, whose roots carry the session actions"
        onPressed: root.openSession()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "launcher"
        description: "Toggle launcher"
        onPressed: root.launcherInterrupted = false
        onReleased: {
            if (!root.launcherInterrupted && !root.hasFullscreen) {
                const screenState = ShellState.forActive();
                root.toggleRoom(screenState, "launcher");
            }
            root.launcherInterrupted = false;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "launcherInterrupt"
        description: "Interrupt launcher keybind"
        onPressed: root.launcherInterrupted = true
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "sidebar"
        description: "Toggle sidebar"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            screenState.sidebar = !screenState.sidebar;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "utilities"
        description: "Toggle utilities"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            screenState.utilities = !screenState.utilities;
        }
    }

    IpcHandler {
        function toggle(): void {
            root.openSession();
        }

        target: "session"
    }

    IpcHandler {
        // Opens the launcher with the field pre-filled. `query ">clip "` is
        // the clipboard manager; the scope grammar makes every other source
        // reachable the same way without another IPC per source.
        function query(q: string): void {
            if (root.hasFullscreen)
                return;
            ShellState.pendingLauncherQuery = q;
            const state = ShellState.forActive();
            if (GlobalConfig.dashboard.navStyle === "living")
                state.openWorldRoom("launcher");
            else
                state.launcher = true;
        }

        target: "launcher"
    }

    IpcHandler {
        function toggle(drawer: string): void {
            if (root.drawerNames.includes(drawer)) {
                if (root.hasFullscreen && ["launcher", "dashboard"].includes(drawer))
                    return;
                const screenState = ShellState.forActive();
                if (["dashboard", "launcher"].includes(drawer))
                    root.toggleRoom(screenState, drawer);
                else
                    screenState[drawer] = !screenState[drawer];
                if (drawer === "dashboard" && screenState.dashboard)
                    screenState.dashboardOpenedByKey = true;
            } else {
                console.warn(lc, `Drawer "${drawer}" does not exist`);
            }
        }

        function list(): string {
            return root.drawerNames.join("\n");
        }

        function isOpen(drawer: string): string {
            if (!root.drawerNames.includes(drawer))
                return "unknown";
            const screenState = ShellState.forActive();
            return screenState && screenState[drawer] ? "1" : "0";
        }

        target: "drawers"
    }

    IpcHandler {
        function open(): void {
            WindowFactory.create();
        }

        target: "nexus"
    }

    IpcHandler {
        // Index into the enabled-section list, left to right. Signature kept
        // stable — it's the one headless path into the dashboard. Out-of-range
        // clamps; a disabled section doesn't shift what the index means.
        function setTab(index: int): string {
            const screenState = ShellState.forActive();
            if (!screenState)
                return "no active screen";
            screenState.dashboardTab = Math.max(0, index);
            return `dashboardTab=${screenState.dashboardTab}`;
        }

        function tab(): string {
            return `${ShellState.forActive()?.dashboardTab ?? -1}`;
        }

        // Id-based selection — immune to which sections happen to be enabled.
        function setSection(id: string): string {
            const screenState = ShellState.forActive();
            if (!screenState)
                return "no active screen";
            if (screenState.selectDashboardSection(id))
                return `section=${screenState.dashboardSection}`;
            const known = (screenState.dashboardSectionIds ?? []).includes(id);
            return known ? `section "${id}" is disabled` : `unknown section "${id}"`;
        }

        function section(): string {
            return ShellState.forActive()?.dashboardSection ?? "";
        }

        // Moves the keyboard focus ring only, so the ring can be verified
        // without changing which pane is showing.
        function focusSection(id: string): string {
            const screenState = ShellState.forActive();
            if (!screenState)
                return "no active screen";
            if (!screenState.focusDashboardSection(id))
                return `unknown section "${id}"`;
            return `focus=${screenState.dashboardFocusSection}`;
        }

        // Grow (opening it if needed) and emphasise `id` — the multi-toggle verb.
        function open(id: string): string {
            const screenState = ShellState.forActive();
            if (!screenState)
                return "no active screen";
            if (screenState.growDashboardSection(id)) {
                if (GlobalConfig.dashboard.navStyle === "living")
                    screenState.openWorldRoom("dashboard");
                else
                    screenState.dashboard = true;
                screenState.dashboardOpenedByKey = true;
                return `open=${formatOpenSections(screenState)}`;
            }
            const known = (screenState.dashboardSectionIds ?? []).includes(id);
            return known ? `section "${id}" is disabled` : `unknown section "${id}"`;
        }

        function fold(id: string): string {
            const screenState = ShellState.forActive();
            if (!screenState)
                return "no active screen";
            if (screenState.foldDashboardSection(id))
                return `open=${formatOpenSections(screenState)}`;
            return `section "${id}" cannot be folded (not open)`;
        }

        // Reorder the open set only — `id` must already be grown.
        function emphasise(id: string): string {
            const screenState = ShellState.forActive();
            if (!screenState)
                return "no active screen";
            if (screenState.emphasiseDashboardSection(id))
                return `open=${formatOpenSections(screenState)}`;
            return `section "${id}" is not open`;
        }

        // "dashboard,media*" — the ordered open set as text, emphasis marked.
        function openSections(): string {
            const screenState = ShellState.forActive();
            if (!screenState)
                return "no active screen";
            return formatOpenSections(screenState);
        }

        // "dashboard:1:+|media:1:+:*|performance:0|weather:1|tasks:1:^" —
        // id:enabled, "+" = grown (in the open set), "*" = emphasised
        // (showing / dashboardSection), "^" = keyboard focus ring. The whole
        // nav state as text, which is what makes it verifiable headlessly.
        function sections(): string {
            const screenState = ShellState.forActive();
            if (!screenState)
                return "no active screen";
            const ids = screenState.dashboardSectionIds ?? [];
            if (ids.length === 0)
                return "unknown (dashboard has not been opened yet)";
            const enabled = screenState.dashboardEnabledIds ?? [];
            const open = screenState.dashboardOpenSections ?? [];
            return ids.map(id => {
                let s = `${id}:${enabled.includes(id) ? 1 : 0}`;
                if (open.includes(id))
                    s += ":+";
                if (id === screenState.dashboardSection)
                    s += ":*";
                if (id === screenState.dashboardFocusSection)
                    s += ":^";
                return s;
            }).join("|");
        }

        // Flips Config.dashboard.show<Section> for this session (config writes
        // are in-memory; shell.json is untouched). "tasks" has no flag.
        function toggleSection(id: string): string {
            const screenState = ShellState.forActive();
            if (!screenState)
                return "no active screen";
            const flag = screenState.toggleDashboardSection(id);
            if (!flag)
                return `section "${id}" cannot be toggled`;
            return `${flag}=${GlobalConfig.dashboard[flag] ? 1 : 0}`;
        }

        target: "dashboard"
    }

    IpcHandler {
        // Headless entry point for the screenshot history previewer: the card
        // lives in the utilities drawer, so `open` raises the drawer AND
        // expands the shelf in one call.
        //
        // Same lazy-singleton trap as FocusMode above: `Screenshots` mounts on
        // first reference, so `count()` right after `open()` can read 0 for
        // ~150ms while rebuild() debounces — poll it.
        function open(): void {
            const screenState = ShellState.forActive();
            if (!screenState)
                return;
            screenState.utilities = true;
            Screenshots.expanded = true;
        }

        function close(): void {
            const screenState = ShellState.forActive();
            Screenshots.closePreview();
            Screenshots.expanded = false;
            if (screenState)
                screenState.utilities = false;
        }

        function toggle(): void {
            const screenState = ShellState.forActive();
            if (screenState?.utilities && Screenshots.expanded)
                close();
            else
                open();
        }

        function preview(index: int): string {
            const screenState = ShellState.forActive();
            if (!screenState)
                return "no active screen";
            if (index === -1) {
                Screenshots.closePreview();
                return "closed";
            }
            if (index < 0 || index >= Screenshots.entries.length)
                return `out of range (0..${Screenshots.entries.length - 1})`;
            screenState.utilities = true;
            Screenshots.expanded = true;
            Screenshots.openPreview(Screenshots.entries[index].path);
            return `preview=${Screenshots.previewPath}`;
        }

        function count(): string {
            return `${Screenshots.entries.length}`;
        }

        function latest(): string {
            return Screenshots.latest?.path ?? "";
        }

        function list(): string {
            return Screenshots.entries.map(e => `${e.saved ? "saved" : "cache"}\t${e.label}\t${e.path}`).join("\n");
        }

        target: "screenshots"
    }

    IpcHandler {
        function info(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Info);
        }

        function success(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Success);
        }

        function warn(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Warning);
        }

        function error(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Error);
        }

        target: "toaster"
    }

    LoggingCategory {
        id: lc

        name: "burl.qml.shortcuts"
        defaultLogLevel: LoggingCategory.Info
    }
}
