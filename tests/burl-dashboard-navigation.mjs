import assert from "node:assert/strict";
import { test } from "node:test";
import { catalog, plain, state as fixture } from "./lib/navigation-state.mjs";
const state = config => fixture(config).root;

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
    const { root } = fixture({ showWeather: true }, { dashboardOpenSection: "media", dashboardSection: "media", dashboardFocusSection: "media" });
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
