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
        searchActive: false, nodeScores: [], filterTimer: { running: false },
        sim: { x: i => points[i][0], y: i => points[i][1] },
        _nx: i => points[i][0], _ny: i => points[i][1],
        _w2sX: x => x, _w2sY: y => y, _s2wX: x => x, _s2wY: y => y,
        _assignNavSlots() {}, _centerOnNode() {}, edgeLayer: { refresh() {} },
    };
    for (const name of ["flushSearch", "isNavigationCandidate", "cycleMatch", "directionalNode", "selectNode", "navDirection", "navigateBack", "cycleLinkedNeighbor"]) {
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

test("filtered arrows skip a closer nonmatch, regardless of graph edges", () => {
    const g = graph([[400, 400], [410, 400], [500, 400], [300, 400]]);
    g.searchActive = true;
    g.nodeScores = [10, 0, 4, 0];
    g.matchIndices = [0, 2];
    g.nodeAdjacency = { 0: [1, 3] };
    g.navDirection(1, 0);
    assert.equal(g.currentNode, 2);
    g.navDirection(-1, 0);
    assert.equal(g.currentNode, 0);
    g.navDirection(-1, 0);
    assert.equal(g.currentNode, 0);
});

test("filtered Tab cycles by rank in either direction, excluding linked nonmatches", () => {
    const g = graph([[400, 400], [410, 400], [500, 400], [300, 400]]);
    g.searchActive = true;
    g.nodeScores = [10, 0, 4, 8];
    g.matchIndices = [0, 3, 2];
    g.nodeAdjacency = { 0: [1] };
    for (const expected of [3, 2, 0]) {
        g.cycleLinkedNeighbor(1);
        assert.equal(g.currentNode, expected);
    }
    g.cycleLinkedNeighbor(-1);
    assert.equal(g.currentNode, 2);
});

test("zero matches cannot acquire a keyboard selection", () => {
    const g = graph([[400, 400], [500, 400]]);
    g.searchActive = true;
    g.nodeScores = [0, 0];
    g.currentNode = -1;
    g.navDirection(1, 0);
    g.cycleLinkedNeighbor(1);
    assert.equal(g.currentNode, -1);
});

test("pending input is applied before navigation", () => {
    const g = graph([[400, 400], [410, 400], [500, 400]]);
    g.filterTimer = { running: true, stop() { this.running = false; } };
    g._applyFilter = () => {
        g.searchActive = true;
        g.nodeScores = [10, 0, 4];
        g.matchIndices = [0, 2];
    };
    g.navDirection(1, 0);
    assert.equal(g.currentNode, 2);
    assert.equal(g.filterTimer.running, false);
});

test("backtracking skips entries excluded by the active query", () => {
    const g = graph([[400, 400], [410, 400], [500, 400]]);
    g.currentNode = 2;
    g.navigationHistory = [0, 1];
    g.searchActive = true;
    g.nodeScores = [10, 0, 4];
    g.navigateBack();
    assert.equal(g.currentNode, 0);
    assert.equal(g.navigationHistory.length, 0);
});
