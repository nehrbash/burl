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
    readonly property int dashboardTab: dashboardEnabledIds.indexOf(dashboardSection)

    property alias bar: intent.bar
    property alias osd: intent.osd
    property alias launcher: intent.launcher
    property alias dashboard: intent.dashboard
    property alias utilities: intent.utilities
    property alias sidebar: intent.sidebar
    property alias dashboardSection: intent.dashboardSection
    readonly property var dashboardOpenSections: intent.dashboardOpenSection ? [intent.dashboardOpenSection] : []
    property alias dashboardFocusSection: intent.dashboardFocusSection
    property alias dashboardDate: intent.dashboardDate

    property bool dashboardWantsKeyboard
    property bool dashboardOpenedByKey
    property var dashboardMaskRects: []
    property var dashboardTrunkRect: null
    property bool dashboardTreeGrown
    property bool dashboardTreePinned
    property bool initialized

    PersistentProperties {
        id: intent
        reloadableId: "screen-intent-" + root.modelData.name
        onLoaded: root.reconcileDashboardSection()
        onReloaded: root.reconcileDashboardSection()

        property bool bar
        property bool osd
        property bool launcher
        property bool dashboard
        property bool utilities
        property bool sidebar
        property string dashboardSection: "dashboard"
        property string dashboardOpenSection
        property string dashboardFocusSection: "dashboard"
        property date dashboardDate: new Date()
    }

    function openWorldRoom(room: string): void {
        // Raise the incoming room first to keep the shared surface mounted.
        if (room === "launcher") {
            root.launcher = true;
            root.dashboard = false;
        } else {
            root.dashboard = true;
            root.launcher = false;
            root.dashboardOpenedByKey = true;
        }
    }

    function toggleWorldRoom(room: string): void {
        const current = root.launcher ? "launcher" : root.dashboard ? "dashboard" : "";
        if (current === room) {
            root.launcher = false;
            root.dashboard = false;
        } else {
            root.openWorldRoom(room);
        }
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

    function storeDashboardOpenSections(ids: var): void {
        intent.dashboardOpenSection = ids.length ? ids[ids.length - 1] : "";
    }

    function growDashboardSection(id: string): bool {
        if (!id)
            return false;
        const ids = root.dashboardEnabledIds;
        if (!ids.includes(id))
            return false;
        root.storeDashboardOpenSections([id]);
        root.dashboardSection = id;
        root.dashboardFocusSection = id;
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
        root.storeDashboardOpenSections(next);
        if (next.length === 0)
            return true;
        const emphasis = next[next.length - 1];
        if (root.dashboardSection !== emphasis) {
            root.dashboardSection = emphasis;
            root.dashboardFocusSection = emphasis;
        }
        return true;
    }

    function foldAllDashboardSections(): void {
        root.storeDashboardOpenSections([]);
    }

    function emphasiseDashboardSection(id: string): bool {
        const open = root.dashboardOpenSections;
        if (!id || !open.includes(id))
            return false;
        const next = open.filter(x => x !== id);
        next.push(id);
        root.storeDashboardOpenSections(next);
        root.dashboardSection = id;
        root.dashboardFocusSection = id;
        return true;
    }

    function setDashboardOpenSections(ids: var): void {
        const list = (ids ?? []).filter(id => root.dashboardEnabledIds.includes(id));
        root.storeDashboardOpenSections(list);
        const emphasis = root.dashboardOpenSections[0] ?? root.dashboardSection;
        if (root.dashboardSection !== emphasis) {
            root.dashboardSection = emphasis;
            root.dashboardFocusSection = emphasis;
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
        root.dashboardFocusSection = id;
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
            root.storeDashboardOpenSections(openFiltered);
        if (!ids.includes(root.dashboardSection))
            root.dashboardSection = openFiltered[0] ?? ids[0] ?? "";
        if (!ids.includes(root.dashboardFocusSection))
            root.dashboardFocusSection = ids[0] ?? "";
    }

    onDashboardChanged: {
        if (root.initialized && !root.dashboard) {
            root.dashboardOpenedByKey = false;
            root.dashboardTreeGrown = false;
            root.dashboardTreePinned = false;
            root.storeDashboardOpenSections([]);
        }
    }
    onDashboardEnabledIdsChanged: root.reconcileDashboardSection()
    Component.onCompleted: {
        root.initialized = true;
        root.reconcileDashboardSection();
    }
}
