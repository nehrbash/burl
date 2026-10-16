import assert from "node:assert/strict";
import { test } from "node:test";
import { state as fixture } from "./lib/navigation-state.mjs";
const state = initial => fixture({}, { ...initial, worldRoom: initial?.launcher ? "launcher" : initial?.dashboard ? "dashboard" : "" });

test("tree shortcut descends from sky without closing the shared surface", () => {
    const { root, transitions } = state({ launcher: true });
    root.toggleWorldRoom("dashboard");
    assert.equal(root.dashboard, true);
    assert.equal(root.launcher, false);
    assert.equal(root.dashboardOpenedByKey, true);
    assert.ok(transitions.every(Boolean));
});

test("launcher shortcut ascends from tree without closing the shared surface", () => {
    const { root, transitions } = state({ dashboard: true });
    root.toggleWorldRoom("launcher");
    assert.equal(root.dashboard, false);
    assert.equal(root.launcher, true);
    assert.ok(transitions.every(Boolean));
});

test("repeating a room shortcut closes and then reopens that room", () => {
    const { root } = state();
    for (const room of ["dashboard", "launcher"]) {
        root.openWorldRoom(room);
        root.toggleWorldRoom(room);
        assert.equal(root.dashboard || root.launcher, false);
        root.toggleWorldRoom(room);
        assert.equal(root[room], true);
    }
});

test("tree shortcut recovers a state with both room flags set", () => {
    const { root } = state({ launcher: true, dashboard: true });
    root.toggleWorldRoom("dashboard");
    assert.equal(root.dashboard, true);
    assert.equal(root.launcher, false);
});


test("normal room commands preserve tabs coexistence", () => {
    const { root } = fixture({ navStyle: "tabs" });
    root.openRoom("launcher", "key");
    root.openRoom("dashboard", "ipc");
    assert.equal(root.launcher && root.dashboard, true);
    root.closeRoom("launcher", "action");
    assert.equal(root.launcher, false);
    assert.equal(root.dashboard, true);
    root.closeWorld("escape");
    assert.equal(root.dashboard, false);
});

test("repeated hover cannot revoke deliberate dashboard opening", () => {
    for (const navStyle of ["living", "tabs"]) {
        const { root } = fixture({ navStyle });
        root.openRoom("dashboard", "key");
        root.setVisible("dashboard", true, "hover");
        assert.equal(root.dashboardOpenedByKey, true);
    }
});

test("hover opens do not claim deliberate activation and IPC upgrades them", () => {
    const { root } = fixture({ navStyle: "tabs" });
    root.openRoom("dashboard", "hover");
    assert.equal(root.dashboardOpenedByKey, false);
    root.openRoom("dashboard", "ipc");
    assert.equal(root.dashboardOpenedByKey, true);
});

test("invalid visibility commands cannot mutate unrelated state", () => {
    const { root } = fixture();
    assert.equal(root.setVisible("dashboardSection", true, "ipc"), false);
    assert.equal(root.toggleVisible("missing", "ipc"), false);
    root.openRoom("missing", "ipc");
    assert.equal(root.dashboard || root.launcher, false);
});

test("world commands remain exclusive in tabs mode", () => {
    const { root } = fixture({ navStyle: "tabs" });
    root.openRoom("launcher", "key");
    root.openWorldRoom("dashboard", "key");
    assert.equal(root.launcher, false);
    assert.equal(root.dashboard, true);
});
