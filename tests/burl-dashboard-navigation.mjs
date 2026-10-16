import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const catalogSource = readFileSync(new URL("../utils/DashboardSections.js", import.meta.url), "utf8");
const catalog = runInNewContext(`${catalogSource.replace(/^\.pragma library\s*/, "")}\n({sections, enabledIds, sectionFlag})`);
const source = readFileSync(new URL("../components/ScreenState.qml", import.meta.url), "utf8");
const plain = value => JSON.parse(JSON.stringify(value));
function state(config = {}) {
    const root = {
        initialized: true,
        dashboardEnabledIds: catalog.enabledIds(config),
        dashboardSectionIds: catalog.sections.map(s => s.id),
        dashboardSection: "dashboard",
        dashboardOpenSections: [],
        dashboardFocusSection: "dashboard",
    };
    root.storeDashboardOpenSections = ids => { root.dashboardOpenSections = ids.length ? [ids[ids.length - 1]] : []; };
    for (const name of ["growDashboardSection", "selectDashboardSection", "selectDashboardTab", "setDashboardOpenSections", "focusDashboardSection", "reconcileDashboardSection"]) {
        const match = source.match(new RegExp(`^    function ${name}\\(([^)]*)\\): \\w+ \\{([\\s\\S]*?)\\n    \\}`, "m"));
        assert.ok(match, name);
        root[name] = runInNewContext(`(function(${match[1].replace(/:\s*\w+/g, "")}) {${match[2]}\n})`, { root });
    }
    return root;
}

test("catalog resolves ordered sections without any view", () => {
    assert.deepEqual(plain(catalog.enabledIds({ showWeather: true, showMedia: true })), ["media", "weather", "tasks"]);
    assert.equal(catalog.sectionFlag("media"), "showMedia");
    assert.equal(catalog.sectionFlag("tasks"), "");
    assert.equal(catalog.sectionFlag("missing"), "");
    assert.equal(new Set(catalog.sections.map(s => s.id)).size, catalog.sections.length);
});

test("pre-view section commands reject disabled and unknown sections", () => {
    const root = state({ showWeather: true });
    assert.equal(root.growDashboardSection("media"), false);
    assert.equal(root.growDashboardSection("missing"), false);
    assert.equal(root.growDashboardSection("weather"), true);
    assert.deepEqual(plain(root.dashboardOpenSections), ["weather"]);
});

test("legacy indices resolve immediately against each screen's enabled order", () => {
    const first = state({ showDashboard: true, showMedia: true });
    const second = state({ showWeather: true });
    first.selectDashboardTab(1);
    second.selectDashboardTab(1);
    assert.equal(first.dashboardSection, "media");
    assert.equal(second.dashboardSection, "tasks");
    second.selectDashboardTab(-5);
    assert.equal(second.dashboardSection, "weather");
    first.selectDashboardTab(99);
    assert.equal(first.dashboardSection, "tasks");
});

test("disabled restored selection folds and focus reconciles without opening a replacement", () => {
    const root = state({ showWeather: true });
    root.dashboardOpenSections = ["media"];
    root.dashboardSection = "media";
    root.dashboardFocusSection = "media";
    root.reconcileDashboardSection();
    assert.deepEqual(plain(root.dashboardOpenSections), []);
    assert.equal(root.dashboardSection, "weather");
    assert.equal(root.dashboardFocusSection, "weather");
});

test("bulk selection rejects unavailable IDs while preserving single-open behavior", () => {
    const root = state({ showWeather: true });
    root.setDashboardOpenSections(["weather", "tasks", "missing"]);
    assert.deepEqual(plain(root.dashboardOpenSections), ["tasks"]);
    root.setDashboardOpenSections(["media"]);
    assert.deepEqual(plain(root.dashboardOpenSections), []);
});

test("focus can reach a disabled tree node for revival without opening it", () => {
    const root = state();
    assert.equal(root.focusDashboardSection("media"), true);
    assert.equal(root.dashboardFocusSection, "media");
    assert.deepEqual(plain(root.dashboardOpenSections), []);
    assert.equal(root.focusDashboardSection("missing"), false);
});
