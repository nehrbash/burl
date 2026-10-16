import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../../components/ScreenState.qml", import.meta.url), "utf8");
const catalogSource = readFileSync(new URL("../../utils/DashboardSections.js", import.meta.url), "utf8");
export const catalog = runInNewContext(`${catalogSource.replace(/^\.pragma library\s*/, "")}\n({sections, enabledIds, sectionFlag})`);
export const plain = value => JSON.parse(JSON.stringify(value));

export function state(config = {}, initial = {}) {
    const transitions = [];
    const initialRoom = initial.worldRoom ?? (initial.launcher && initial.dashboard ? "both" : initial.launcher ? "launcher" : initial.dashboard ? "dashboard" : "");
    const intent = new Proxy({
        launcher: false, dashboard: false, worldRoom: "",
        dashboardSection: "dashboard", dashboardOpenSection: "", dashboardFocusSection: "dashboard",
        ...initial, worldRoom: initialRoom,
    }, {
        set(target, key, value) {
            target[key] = value;
            if (key === "worldRoom") transitions.push(value !== "");
            return true;
        },
    });
    const session = { openedByKey: false, pinned: false };
    const root = {
        initialized: true,
        dashboardConfig: { navStyle: "living", ...config },
        dashboardEnabledIds: catalog.enabledIds(config),
        dashboardSectionIds: catalog.sections.map(s => s.id),
    };
    for (const key of ["dashboardSection", "dashboardFocusSection", "dashboardDate", "bar", "osd", "sidebar", "utilities"])
        Object.defineProperty(root, key, { get: () => intent[key] });
    for (const key of ["launcher", "dashboard"])
        Object.defineProperty(root, key, { get: () => intent.worldRoom === key || intent.worldRoom === "both" });
    Object.defineProperties(root, {
        dashboardOpenSections: { get: () => intent.dashboardOpenSection ? [intent.dashboardOpenSection] : [] },
        dashboardOpenedByKey: { get: () => session.openedByKey },
        dashboardTreePinned: { get: () => session.pinned },
    });
    for (const match of source.matchAll(/^    function (\w+)\(([^)]*)\): \w+ \{([\s\S]*?)\n    \}/gm)) {
        root[match[1]] = runInNewContext(`(function(${match[2].replace(/:\s*\w+/g, "")}) {${match[3]}\n})`, {
            root, intent, session, DashboardSections: catalog,
        });
    }
    assert.ok(root.openRoom);
    return { root, intent, session, transitions };
}
