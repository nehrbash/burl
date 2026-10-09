import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../components/ScreenState.qml", import.meta.url), "utf8");
function state(initial = {}) {
    const transitions = [];
    const root = new Proxy({ launcher: false, dashboard: false, ...initial }, {
        set(target, key, value) {
            target[key] = value;
            if (key === "launcher" || key === "dashboard")
                transitions.push(target.launcher || target.dashboard);
            return true;
        },
    });
    for (const name of ["openWorldRoom", "toggleWorldRoom"]) {
        const match = source.match(new RegExp(`^    function ${name}\\(([^)]*)\\): void \\{([\\s\\S]*?)\\n    \\}`, "m"));
        assert.ok(match, name);
        root[name] = runInNewContext(`(function(${match[1].replace(/:\s*\w+/g, "")}) {${match[2]}\n})`, { root });
    }
    return { root, transitions };
}

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
