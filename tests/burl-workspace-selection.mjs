import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const shellState = readFileSync(new URL("../services/ShellState.qml", import.meta.url), "utf8");

function selector(calls, screens) {
    const match = shellState.match(/^    function selectWorkspace\(([^)]*)\): void \{([\s\S]*?)\n    \}/m);
    assert.ok(match, "ShellState.selectWorkspace exists");
    const params = match[1].replace(/:\s*[\w]+/g, "");
    return runInNewContext(`(function(${params}) {${match[2]}\n})`, {
        states: { instances: screens },
        Hypr: {
            batchDispatch: requests => calls.push({
                requests: Array.from(requests),
                surfaceOpen: screens.some(state => state.launcher || state.dashboard),
            }),
        },
    });
}

test("workspace selection closes sky and tree on every screen before dispatch", () => {
    const calls = [];
    const screens = [
        { launcher: true, dashboard: false },
        { launcher: false, dashboard: true },
        { launcher: true, dashboard: true },
    ];
    const selectWorkspace = selector(calls, screens);
    selectWorkspace(["workspace 4"]);

    assert.deepEqual(screens.map(({ launcher, dashboard }) => [launcher, dashboard]), [
        [false, false],
        [false, false],
        [false, false],
    ]);
    assert.deepEqual(calls, [{ requests: ["workspace 4"], surfaceOpen: false }]);
});

test("choosing the current workspace closes overlays without dispatching", () => {
    const calls = [];
    const screen = { launcher: true, dashboard: true };
    const selectWorkspace = selector(calls, [screen]);
    selectWorkspace([]);

    assert.deepEqual([screen.launcher, screen.dashboard], [false, false]);
    assert.deepEqual(calls, []);
});

test("workspace controls close only after an intentional click or wheel selection", () => {
    const workspaces = readFileSync(new URL("../modules/bar/components/workspaces/Workspaces.qml", import.meta.url), "utf8");
    const specials = readFileSync(new URL("../modules/bar/components/workspaces/SpecialWorkspaces.qml", import.meta.url), "utf8");
    const bar = readFileSync(new URL("../modules/bar/Bar.qml", import.meta.url), "utf8");
    const graph = readFileSync(new URL("../modules/launcher/GraphView.qml", import.meta.url), "utf8");

    assert.match(workspaces, /onClicked: event => \{[\s\S]*ShellState\.selectWorkspace\(reqs\)/);
    assert.doesNotMatch(workspaces, /onPressed: event =>/);
    assert.match(specials, /onClicked: event => \{[\s\S]*ShellState\.selectWorkspace\(/);
    assert.match(bar, /function handleWheel\([\s\S]*ShellState\.selectWorkspace\(/);
    assert.match(graph, /kind: "workspace",[\s\S]*onClicked: \(\) => ShellState\.selectWorkspace\(/);
});
