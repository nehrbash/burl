import QtQuick
import Quickshell
import Burl.Config
import "../utils/DashboardSections.js" as DashboardSections

Scope {
    id: root

    required property ShellScreen modelData
    readonly property var dashboardConfig: GlobalConfig.forScreen(modelData.name).dashboard
    readonly property var dashboardSections: DashboardSections.sections
    readonly property var dashboardSectionIds: dashboardSections.map(section => section.id)
    readonly property var dashboardEnabledIds: DashboardSections.enabledIds(dashboardConfig)
    readonly property bool worldOpen: intent.worldRoom !== ""
    readonly property string worldRoom: intent.worldRoom
    readonly property int dashboardTab: dashboardEnabledIds.indexOf(dashboardSection)

    readonly property bool bar: intent.bar
    readonly property bool osd: intent.osd
    readonly property bool launcher: intent.worldRoom === "launcher" || intent.worldRoom === "both"
    readonly property bool dashboard: intent.worldRoom === "dashboard" || intent.worldRoom === "both"
    readonly property bool utilities: intent.utilities
    readonly property bool sidebar: intent.sidebar
    readonly property string dashboardSection: intent.dashboardSection
    readonly property var dashboardOpenSections: intent.dashboardOpenSection ? [intent.dashboardOpenSection] : []
    readonly property string dashboardFocusSection: intent.dashboardFocusSection
    readonly property date dashboardDate: intent.dashboardDate

    readonly property bool dashboardOpenedByKey: session.openedByKey
    readonly property bool dashboardTreePinned: session.pinned
    property bool initialized

    QtObject {
        id: session
        property bool openedByKey
        property bool pinned
    }

    PersistentProperties {
        id: intent
        reloadableId: "screen-intent-" + root.modelData.name
        onLoaded: { root.migrateRoom(); root.reconcileRoom(); root.reconcileDashboardSection(); }
        onReloaded: { root.migrateRoom(); root.reconcileRoom(); root.reconcileDashboardSection(); }

        property bool bar
        property bool osd
        property string worldRoom
        // Consumed once when restoring the pre-scalar navigation schema.
        property bool launcher
        property bool dashboard
        property bool utilities
        property bool sidebar
        property string dashboardSection: "dashboard"
        property string dashboardOpenSection
        property string dashboardFocusSection: "dashboard"
        property date dashboardDate: new Date()
    }

    function setVisible(name: string, visible: bool, origin: string): bool {
        if (name === "launcher" || name === "dashboard") {
            if (visible)
                root.openRoom(name, origin);
            else
                root.closeRoom(name, origin);
        } else if (["bar", "osd", "utilities", "sidebar"].includes(name)) {
            intent[name] = visible;
        } else {
            return false;
        }
        return true;
    }

    function toggleVisible(name: string, origin: string): bool {
        if (!["bar", "osd", "launcher", "dashboard", "utilities", "sidebar"].includes(name))
            return false;
        return root.setVisible(name, !root[name], origin);
    }

    function openRoom(room: string, origin: string): void {
        if (room !== "launcher" && room !== "dashboard")
            return;
        if (root.dashboardConfig.navStyle === "living") {
            root.openWorldRoom(room, origin);
        } else {
            if (room === "dashboard" && (!root.dashboard || origin === "key" || origin === "ipc"))
                session.openedByKey = origin === "key" || origin === "ipc";
            const other = room === "launcher" ? root.dashboard : root.launcher;
            intent.worldRoom = other ? "both" : room;
        }
    }

    function toggleRoom(room: string, origin: string): void {
        if (room !== "launcher" && room !== "dashboard")
            return;
        if (root[room])
            root.closeRoom(room, "toggle");
        else
            root.openRoom(room, origin);
    }

    function closeRoom(room: string, reason: string): void {
        if (room !== "launcher" && room !== "dashboard")
            return;
        if (intent.worldRoom === "both")
            intent.worldRoom = room === "launcher" ? "dashboard" : "launcher";
        else if (intent.worldRoom === room)
            intent.worldRoom = "";
    }

    function closeWorld(reason: string): void {
        intent.worldRoom = "";
    }

    function openWorldRoom(room: string, origin: var): void {
        if (room !== "launcher" && room !== "dashboard")
            return;
        if (room === "dashboard" && (!root.dashboard || !origin || origin === "key" || origin === "ipc"))
            session.openedByKey = !origin || origin === "key" || origin === "ipc";
        intent.worldRoom = room;
    }

    function toggleWorldRoom(room: string, origin: var): void {
        const current = root.launcher ? "launcher" : root.dashboard ? "dashboard" : "";
        if (current === room)
            root.closeWorld("toggle");
        else
            root.openWorldRoom(room, origin);
    }

    function migrateRoom(): void {
        if (intent.launcher || intent.dashboard) {
            intent.worldRoom = intent.launcher && intent.dashboard ? "both" : intent.launcher ? "launcher" : "dashboard";
            intent.launcher = false;
            intent.dashboard = false;
        }
    }

    function reconcileRoom(): void {
        if (!["", "launcher", "dashboard", "both"].includes(intent.worldRoom))
            intent.worldRoom = "";
        if (root.dashboardConfig.navStyle === "living" && intent.worldRoom === "both")
            intent.worldRoom = "launcher";
    }

    function setDashboardDate(date: date): void {
        intent.dashboardDate = date;
    }

    function setDashboardPinned(pinned: bool): void {
        session.pinned = root.dashboard && pinned;
    }

    Connections {
        target: root.dashboardConfig
        function onNavStyleChanged(): void { root.reconcileRoom(); }
    }

    function dashboardSectionFlag(id: string): string {
        return DashboardSections.sectionFlag(id);
    }

    function selectDashboardTab(index: int): bool {
        const ids = root.dashboardEnabledIds;
        if (ids.length === 0)
            return false;
        return root.selectDashboardSection(ids[Math.max(0, Math.min(ids.length - 1, index))]);
    }

    function growDashboardSection(id: string): bool {
        if (!id)
            return false;
        const ids = root.dashboardEnabledIds;
        if (!ids.includes(id))
            return false;
        intent.dashboardOpenSection = id;
        intent.dashboardSection = id;
        intent.dashboardFocusSection = id;
        return true;
    }

    function selectDashboardSection(id: string): bool {
        return root.growDashboardSection(id);
    }

    function foldDashboardSection(id: string): bool {
        const open = root.dashboardOpenSections;
        if (!id || open.length === 0 || !open.includes(id))
            return false;
        const next = open.filter(x => x !== id);
        intent.dashboardOpenSection = next[next.length - 1] ?? "";
        if (next.length === 0)
            return true;
        const emphasis = next[next.length - 1];
        if (root.dashboardSection !== emphasis) {
            intent.dashboardSection = emphasis;
            intent.dashboardFocusSection = emphasis;
        }
        return true;
    }

    function foldAllDashboardSections(): void {
        intent.dashboardOpenSection = "";
    }

    function emphasiseDashboardSection(id: string): bool {
        const open = root.dashboardOpenSections;
        if (!id || !open.includes(id))
            return false;
        const next = open.filter(x => x !== id);
        next.push(id);
        intent.dashboardOpenSection = next[next.length - 1] ?? "";
        intent.dashboardSection = id;
        intent.dashboardFocusSection = id;
        return true;
    }

    function setDashboardOpenSections(ids: var): void {
        const list = (ids ?? []).filter(id => root.dashboardEnabledIds.includes(id));
        intent.dashboardOpenSection = list[list.length - 1] ?? "";
        const emphasis = root.dashboardOpenSections[0] ?? root.dashboardSection;
        if (root.dashboardSection !== emphasis) {
            intent.dashboardSection = emphasis;
            intent.dashboardFocusSection = emphasis;
        }
    }

    function stepDashboardSection(delta: int): void {
        const ids = root.dashboardEnabledIds;
        if (ids.length === 0)
            return;
        const i = ids.indexOf(root.dashboardSection);
        const next = Math.max(0, Math.min(ids.length - 1, (i < 0 ? 0 : i) + delta));
        root.selectDashboardSection(ids[next]);
    }

    function selectDashboardEdge(last: bool): void {
        const ids = root.dashboardEnabledIds;
        if (ids.length > 0)
            root.selectDashboardSection(ids[last ? ids.length - 1 : 0]);
    }

    // Withered tree nodes must remain reachable so keyboard users can revive them.
    function focusDashboardSection(id: string): bool {
        const ids = root.dashboardSectionIds;
        if (!id || (ids.length > 0 && !ids.includes(id)))
            return false;
        intent.dashboardFocusSection = id;
        return true;
    }

    function toggleDashboardSection(id: string): string {
        const flag = root.dashboardSectionFlag(id);
        if (!flag)
            return "";
        // Section toggles retain their global scope; monitor overrides remain authoritative.
        GlobalConfig.dashboard[flag] = !GlobalConfig.dashboard[flag];
        return flag;
    }

    function reconcileDashboardSection(): void {
        if (!root.initialized)
            return;
        const ids = root.dashboardEnabledIds;
        const openFiltered = root.dashboardOpenSections.filter(id => ids.includes(id)).slice(-1);
        if (JSON.stringify(openFiltered) !== JSON.stringify(root.dashboardOpenSections))
            intent.dashboardOpenSection = openFiltered[0] ?? "";
        if (!ids.includes(root.dashboardSection))
            intent.dashboardSection = openFiltered[0] ?? ids[0] ?? "";
        if (!ids.includes(root.dashboardFocusSection))
            intent.dashboardFocusSection = ids[0] ?? "";
    }

    onDashboardChanged: {
        if (root.initialized && !root.dashboard) {
            session.openedByKey = false;
            session.pinned = false;
            intent.dashboardOpenSection = "";
        }
    }
    onDashboardEnabledIdsChanged: root.reconcileDashboardSection()
    Component.onCompleted: {
        root.initialized = true;
        root.reconcileDashboardSection();
    }
}
