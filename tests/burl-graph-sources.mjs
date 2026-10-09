import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const source = readFileSync(new URL('../modules/launcher/GraphView.qml', import.meta.url), 'utf8');
function graph() {
    let scheduled = false;
    const g = {
        paused: true, layoutReady: true, transitioning: false,
        rebuildPending: false, edgesPending: false, resizePending: false,
        sourceNodes: ['a'], nodes: ['a'], sourceEdges: [], edges: [], rebuilds: 0,
        rebuildTimer: { restart() { scheduled = true; } },
        resizeTimer: { restart() {} },
        rebuild() { g.nodes = [...g.sourceNodes]; g.rebuilds++; },
        edgeLayer: { refresh() { g.edges = [...g.sourceEdges]; } },
    };
    const deferred = source.match(/readonly property bool updatesDeferred: (.+)/)[1];
    Object.defineProperty(g, 'updatesDeferred', { get: () => runInNewContext(deferred, g) });
    for (const name of ['requestRebuild', 'requestEdges', 'flushSources']) {
        const body = source.match(new RegExp(`function ${name}\\(\\): void \\{([\\s\\S]*?)\\n    \\}`))[1];
        g[name] = runInNewContext(`(function() { ${body} })`, g);
    }
    const resume = source.match(/onUpdatesDeferredChanged: \{([\s\S]*?)\n    \}/)[1];
    g.resume = runInNewContext(`(function() { ${resume} })`, g);
    g.tick = () => { if (scheduled) { scheduled = false; g.flushSources(); } };
    g.scheduled = () => scheduled;
    return g;
}

test('hidden source bursts coalesce and replay the latest structural state after arrival', () => {
    const g = graph();
    for (let i = 0; i < 20; i++) {
        g.sourceNodes = ['a', String(i)];
        g.requestRebuild();
        g.tick();
    }
    assert.equal(g.scheduled(), false);
    assert.equal(g.rebuilds, 0);
    g.paused = false;
    g.transitioning = true;
    g.resume();
    g.tick();
    assert.equal(g.rebuilds, 0);
    g.transitioning = false;
    g.resume();
    g.tick();
    assert.equal(g.rebuilds, 1);
    assert.deepEqual(g.nodes, ['a', '19']);
    assert.equal(g.rebuildPending, false);
});

test('closing before the debounce expires preserves its pending work', () => {
    const g = graph();
    g.paused = false;
    g.requestRebuild();
    g.paused = true;
    g.tick();
    assert.equal(g.rebuilds, 0);
    assert.equal(g.rebuildPending, true);
    g.paused = false;
    g.resume();
    g.tick();
    assert.equal(g.rebuilds, 1);
});

test('link-only changes replay even when the node set is unchanged', () => {
    const g = graph();
    g.sourceEdges = ['a-b'];
    g.requestEdges();
    g.sourceEdges = ['a-c'];
    g.requestEdges();
    assert.deepEqual(g.edges, []);
    g.paused = false;
    g.resume();
    g.tick();
    assert.deepEqual(g.edges, ['a-c']);
    assert.equal(g.rebuilds, 0);
    assert.equal(g.edgesPending, false);
});

test('first hidden preload remains available before the layout is ready', () => {
    const g = graph();
    g.layoutReady = false;
    g.sourceNodes.push('b');
    g.requestRebuild();
    g.tick();
    assert.deepEqual(g.nodes, ['a', 'b']);
    assert.equal(g.rebuilds, 1);
    g.layoutReady = true;
    g.requestRebuild();
    assert.equal(g.scheduled(), false);
});

test('all source callbacks queue work and warmup preserves the sim pause binding', () => {
    const connections = source.slice(source.indexOf('    Connections {'), source.indexOf('    ForceSim {'));
    assert.doesNotMatch(connections, /rebuildTimer\.restart|edgeLayer\.refresh/);
    assert.match(connections, /onRoamLinksChanged\(\) \{ root\.requestEdges\(\); \}/);
    assert.match(source, /onTriggered: root\.flushSources\(\)/);
    assert.match(source, /paused: root\.paused && !root\.preparing/);
    assert.doesNotMatch(source, /sim\.paused\s*=/);
});
