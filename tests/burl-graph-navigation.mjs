import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../modules/launcher/GraphView.qml", import.meta.url), "utf8");
function graph(points) {
    const context = {
        nodes: points.map((_, i) => ({ id: String(i) })), currentNode: 0,
        matchIndices: [], currentMatchIndex: 0, navigationHistory: [], browsing: false,
        width: 1200, height: 900, nodeAdjacency: {},
        sim: { x: i => points[i][0], y: i => points[i][1] },
        _nx: i => points[i][0], _ny: i => points[i][1],
        _w2sX: x => x, _w2sY: y => y, _s2wX: x => x, _s2wY: y => y,
        _assignNavSlots() {}, _centerOnNode() {}, edgeLayer: { refresh() {} },
    };
    for (const name of ["directionalNode", "selectNode", "navDirection", "navigateBack", "cycleLinkedNeighbor"]) {
        const match = source.match(new RegExp(`^    function ${name}\\(([^)]*)\\): \\w+ \\{([\\s\\S]*?)\\n    \\}`, "m"));
        assert.ok(match, name);
        context[name] = runInNewContext(`(function(${match[1].replace(/:\s*\w+/g, "")}) {${match[2]}\n})`, context);
    }
    return context;
}

test("arrows reach visible nodes with an empty search and no graph edge", () => {
    const g = graph([[400, 400], [500, 400], [420, 600], [300, 400]]);
    g.navDirection(1, 0);
    assert.equal(g.currentNode, 1);
    g.navDirection(-1, 0);
    assert.equal(g.currentNode, 0);
    assert.equal(g.browsing, true);
});

test("an unrelated node ahead beats a linked node outside the direction", () => {
    const g = graph([[400, 400], [410, 500], [510, 400]]);
    g.nodeAdjacency[0] = [1];
    g.matchIndices = [1];
    assert.equal(g.directionalNode(1, 0), 2);
});

test("no node in a direction preserves selection", () => {
    const g = graph([[400, 400], [500, 400]]);
    g.navDirection(-1, 0);
    assert.equal(g.currentNode, 0);
    assert.equal(g.navigationHistory.length, 0);
});

test("backtracking retraces selections without adding another history entry", () => {
    const g = graph([[400, 400], [500, 400], [600, 400]]);
    g.selectNode(1);
    g.selectNode(2);
    g.navigateBack();
    assert.equal(g.currentNode, 1);
    g.cycleLinkedNeighbor(-1);
    assert.equal(g.currentNode, 0);
    assert.equal(g.navigationHistory.length, 0);
});

test("Tab visits linked nodes and survives a disconnected node", () => {
    const g = graph([[400, 400], [500, 400], [600, 400]]);
    g.nodeAdjacency = { 0: [1, 2], 1: [0, 2], 2: [] };
    g.cycleLinkedNeighbor(1);
    assert.equal(g.currentNode, 1);
    g.cycleLinkedNeighbor(1);
    assert.equal(g.currentNode, 2);
    g.cycleLinkedNeighbor(1);
    assert.equal(g.currentNode, 2);
});
