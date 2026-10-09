import Quickshell
import Burl.Config

PersistentProperties {
    id: root

    // Everything declared here is copied over by PersistentProperties on a
    // config reload, so no property in this file may carry a binding that is
    // meant to be re-evaluated after a reload — the restore overwrites the
    // value and destroys the binding. Plain state only; derived values belong
    // in the components that consume them.
    required property ShellScreen modelData

    // Drawer visibilities. The `drawers` IPC target used to discover these by
    // "every boolean property on ScreenState", so the whitelist now lives in
    // modules/Shortcuts.qml (drawerNames) — add a drawer here AND there.
    property bool bar
    property bool osd
    property bool launcher
    property bool dashboard
    property bool utilities
    property bool sidebar

    // Dashboard navigation.
    //
    // `dashboardSection` — a stable string id — is the authority for single-
    // selection nav styles ("tabs", "tree") AND the compat mirror of the
    // EMPHASIS for the multi-toggle "living" style: it is always
    // `dashboardOpenSections[dashboardOpenSections.length - 1]`. Every
    // mutation function below writes both in the same call, so nothing that
    // already reads `dashboardSection` (hyprland.lua, actions.lua, the band,
    // Tabs.qml) needs to change to keep working.
    //
    // `dashboardOpenSections` is the set of GROWN sections. It holds AT MOST
    // ONE: growing a section replaces whatever was grown before, so there is
    // never a second scroll left docked and bobbing beside the canopy. Kept as
    // an array rather than collapsed back into `dashboardSection` because
    // EMPTY is a real, common state — the tree opens bare and folding the one
    // open section returns to a bare canopy, and `dashboardSection` (the
    // tab-bar/IPC compat mirror) has no way to say "none".
    //
    // `dashboardTab` is a COMPAT MIRROR: an index into the ENABLED subset, as
    // shown left to right. It is what the dashboard IPC and the old TabBar
    // speak, and writing it selects the section at that position. It is not
    // the authority because an index into a filtered list silently re-points
    // at a different pane the moment a section is disabled in settings.
    //
    // `dashboardFocusSection` is the keyboard focus ring, deliberately
    // separate from the selection: arrowing across the nav must not
    // instantiate the panes it passes over.
    //
    // The two id lists are published by modules/dashboard/Content.qml (it is
    // the only place that can read the per-screen attached Config), so they
    // are empty until the dashboard has been opened once in this process.
    property string dashboardSection: "dashboard"
    // Bare by default: opening the tree shows the canopy, not a section that
    // nobody asked for.
    property var dashboardOpenSections: []
    property int dashboardTab
    property string dashboardFocusSection: "dashboard"
    property var dashboardSectionIds: []
    property var dashboardEnabledIds: []
    // Set when dashboardTab was written before the id lists existed, so the
    // pre-open `dashboard setTab` IPC still lands once Content publishes them.
    property bool dashboardTabPending
    // Published by Content: the dashboard is open AND wants keyboard focus.
    // ContentWindow reads this to decide WlrLayershell.keyboardFocus.
    property bool dashboardWantsKeyboard
    // Set by the keybind/IPC paths that open the dashboard deliberately, so a
    // merely hover-opened dashboard does not start eating keystrokes.
    property bool dashboardOpenedByKey
    property date dashboardDate: new Date()

    // --- living-tree ("navStyle: living") state --------------------------
    //
    // Published by modules/dashboard/tree/LivingTree.qml, committed exactly
    // once per user action (grow/fold/emphasise/close) — never per animation
    // frame. Consumed by modules/drawers/Regions.qml to build the fixed-slot
    // input mask.
    // Rects are in the same coordinate frame as the Panels item's children
    // (i.e. before the bar-width / border-thickness offset Regions.qml's `R`
    // component applies).
    property var dashboardMaskRects: [] // [{x,y,width,height}, ...], <= 8 slots
    property var dashboardTrunkRect: null // {x,y,width,height} or null
    // True for the whole grown episode (mask armed). False when nothing is
    // grown/animating-open. Drives whether the rects above contribute to the
    // committed mask at all.
    property bool dashboardTreeGrown: false
    // Middle-click-to-pin: suppresses ContentWindow's focus grab
    // for the episode so the tree stays up while the user clicks elsewhere.
    property bool dashboardTreePinned: false

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
        if (!id)
            return "";
        const flag = `show${id.charAt(0).toUpperCase()}${id.slice(1)}`;
        return GlobalConfig.dashboard[flag] === undefined ? "" : flag;
    }

    // Grows `id`, REPLACING whatever was grown. One section at a time: the
    // multi-open variant left every previously grown section as a rolled
    // scroll docked under its own orb, which read as litter rather than as
    // state. This is the one function that can both open and select, which is
    // why every call site (selectDashboardSection below, the IPC
    // setTab/setSection, digit keys, wheel) routes through it.
    function growDashboardSection(id: string): bool {
        if (!id)
            return false;
        const ids = root.dashboardEnabledIds;
        // Before Content has published the lists, take the id on trust —
        // reconcileDashboardSection() validates it as soon as they arrive.
        if (ids.length > 0 && !ids.includes(id))
            return false;
        root.dashboardOpenSections = [id];
        root.dashboardSection = id;
        root.dashboardFocusSection = id;
        return true;
    }

    // Kept verbatim (name + signature) because it is the pre-existing entry
    // point every nav style, the IPC and hyprland.lua already call. "Select"
    // means emphasise this one, growing it if needed — for "tabs"/"tree"
    // (always a single-element open set) that is the same as replacing the
    // selection.
    function selectDashboardSection(id: string): bool {
        return root.growDashboardSection(id);
    }

    // Removes `id` from the open set, which (being single-open) empties it.
    // The set may end up EMPTY — the living tree needs
    // "fold the one I am in and show me the whole canopy again", and that is a
    // fold, not a close (closing the whole surface is `dashboard = false`).
    // `dashboardSection` deliberately keeps its last value in that case: it is
    // the compat mirror the tab bar and the IPC read, and neither has a
    // representation for "no section".
    function foldDashboardSection(id: string): bool {
        const open = root.dashboardOpenSections;
        if (!id || open.length === 0 || !open.includes(id))
            return false;
        const next = open.filter(x => x !== id);
        root.dashboardOpenSections = next;
        if (next.length === 0)
            return true;
        const emphasis = next[next.length - 1];
        if (root.dashboardSection !== emphasis) {
            root.dashboardSection = emphasis;
            root.dashboardFocusSection = emphasis;
        }
        return true;
    }

    // Folds every grown section at once, leaving the tree bare. Same empty-set
    // semantics as foldDashboardSection above: `dashboardSection` keeps its last
    // value as the tab-bar/IPC compat mirror, since neither can say "none".
    function foldAllDashboardSections(): void {
        root.dashboardOpenSections = [];
    }

    // Moves `id` to the end of the open set without changing membership.
    // Returns false if `id` is not currently grown — use
    // growDashboardSection to grow-and-emphasise in one call.
    function emphasiseDashboardSection(id: string): bool {
        const open = root.dashboardOpenSections;
        if (!id || !open.includes(id))
            return false;
        const next = open.filter(x => x !== id);
        next.push(id);
        root.dashboardOpenSections = next;
        root.dashboardSection = id;
        root.dashboardFocusSection = id;
        return true;
    }

    // Wholesale replace of the open set (IPC). Single-open, so only the LAST
    // id of a longer list survives — and an empty list is honoured, since bare
    // is a legitimate state to ask for.
    function setDashboardOpenSections(ids: var): void {
        const list = (ids ?? []).filter(id => !!id);
        root.dashboardOpenSections = list.length > 0 ? [list[list.length - 1]] : [];
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

    function focusDashboardSection(id: string): bool {
        const ids = root.dashboardSectionIds;
        if (!id || (ids.length > 0 && !ids.includes(id)))
            return false;
        root.dashboardFocusSection = id;
        return true;
    }

    // Flips the section's config flag. Returns the flag name, or "" if the
    // section has none (tasks) or the id is unknown. Global, not per-screen:
    // per-monitor overrides only come from shell.json. Deliberately NOT
    // overloaded with grow/fold semantics — it keeps meaning "wither/revive
    // the section" for IPC and the living tree's ctrl+click.
    function toggleDashboardSection(id: string): string {
        const flag = root.dashboardSectionFlag(id);
        if (!flag)
            return "";
        GlobalConfig.dashboard[flag] = !GlobalConfig.dashboard[flag];
        return flag;
    }

    function syncDashboardTab(): void {
        const i = root.dashboardEnabledIds.indexOf(root.dashboardSection);
        if (i >= 0 && root.dashboardTab !== i)
            root.dashboardTab = i;
    }

    // Runs whenever the enabled set changes: the section that was showing (or
    // grown) may have just been disabled, in which case fall back rather than
    // leaving the view pointed at a pane no longer in the model.
    function reconcileDashboardSection(): void {
        const ids = root.dashboardEnabledIds;
        if (ids.length === 0)
            return;
        if (root.dashboardTabPending) {
            root.dashboardTabPending = false;
            root.growDashboardSection(ids[Math.max(0, Math.min(ids.length - 1, root.dashboardTab))]);
        }
        // A section that was grown and has since been disabled is dropped —
        // and NOT replaced by ids[0].
        const openFiltered = root.dashboardOpenSections.filter(id => ids.includes(id));
        if (openFiltered.length !== root.dashboardOpenSections.length)
            root.dashboardOpenSections = openFiltered;
        if (!ids.includes(root.dashboardSection))
            root.dashboardSection = root.dashboardOpenSections[0] ?? ids[0];
        if (!root.dashboardSectionIds.includes(root.dashboardFocusSection))
            root.dashboardFocusSection = root.dashboardSection;
        root.syncDashboardTab();
    }

    onDashboardChanged: {
        if (!root.dashboard) {
            root.dashboardOpenedByKey = false;
            // A closed episode leaves no residue for the next open.
            root.dashboardTreeGrown = false;
            root.dashboardTreePinned = false;
            // Next open starts on a bare canopy, not on whatever was grown
            // when the surface was dismissed.
            root.dashboardOpenSections = [];
        }
    }
    onDashboardSectionChanged: root.syncDashboardTab()
    onDashboardEnabledIdsChanged: root.reconcileDashboardSection()
    // The compat direction: an index write (IPC, TabBar, flick) resolves to an
    // id. Assignments settle after one hop because both sides only write when
    // the value actually differs.
    onDashboardTabChanged: {
        const ids = root.dashboardEnabledIds;
        if (ids.length === 0) {
            root.dashboardTabPending = true;
            return;
        }
        const id = ids[Math.max(0, Math.min(ids.length - 1, root.dashboardTab))];
        if (id === root.dashboardSection)
            root.syncDashboardTab(); // clamp an out-of-range write back into range
        else
            root.selectDashboardSection(id);
    }
}
