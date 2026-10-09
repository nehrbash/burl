import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../modules/launcher/GraphEdges.qml", import.meta.url), "utf8");
const body = source.match(/    function rebuildPaths\(\): void \{([\s\S]*?)\n    \}/)[1];

function edges(overrides = {}) {
    const graph = {
        snap: [0, 0, 5, 100, 0, 5, 100, 100, 5, 200, 100, 5],
        edgePairs: [{ x: 0, y: 1 }, { x: 1, y: 2 }, { x: 2, y: 3 }],
        width: 200, height: 200, highlightFocus: -1, elevationDepth: 3,
        depthToMatch: {}, currentNode: -1, navSlots: [], nodeAdjacency: {},
        _nx(i) { return this.snap[i * 3]; },
        _ny(i) { return this.snap[i * 3 + 1]; },
        ...overrides,
    };
    const context = { graph, progress: 1, filtering: false, paths: [], ...overrides };
    context.rebuild = runInNewContext(`(function() { ${body} })`, context);
    return context;
}

const count = path => (path.match(/M /g) ?? []).length;

test("all graph links survive the scene graph renderer", () => {
    const scene = edges();
    scene.rebuild();
    assert.equal(count(scene.paths[0]), 3);
    assert.equal(scene.paths.slice(1).join(""), "");
    assert.match(scene.paths[0], /100 0 M 100 0/);
});

test("highlight and search depth retain separate edge brightness bands", () => {
    const scene = edges({ highlightFocus: 0 });
    scene.rebuild();
    assert.equal(count(scene.paths[1]), 1);
    assert.equal(count(scene.paths[0]), 2);
    scene.graph.highlightFocus = -1;
    scene.filtering = true;
    scene.graph.depthToMatch = { 0: 0, 1: 1, 2: 4, 3: 5 };
    scene.rebuild();
    assert.deepEqual(Array.from(scene.paths.slice(0, 3), count), [1, 1, 1]);
});

test("partial reveal ends halfway along the curve, then reaches the node", () => {
    const scene = edges({ progress: 0.5 });
    scene.rebuild();
    const numbers = scene.paths[0].split(" M ")[0].match(/-?\d+(?:\.\d+)?/g).map(Number);
    [0, 0, 25, -3.5, 50, -3.5].forEach((value, i) => assert.ok(Math.abs(numbers[i] - value) < 1e-9));
    scene.progress = 1;
    scene.rebuild();
    const end = scene.paths[0].split(" M ")[0].split(" ").slice(-2).map(Number);
    assert.deepEqual(end, [100, 0]);
});

test("preview connectors only follow real links with available positions", () => {
    const scene = edges({ currentNode: 0, navSlots: [1, 2, 99], nodeAdjacency: { 0: [1, 99] } });
    scene.rebuild();
    assert.equal(scene.paths[3], "M 0 0 L 100 0");
    scene.graph.snap = [];
    scene.rebuild();
    assert.equal(scene.paths.join(""), "");
});
