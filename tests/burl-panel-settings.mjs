import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const graph = read('modules/launcher/GraphView.qml');
const launcher = read('modules/nexus/pages/panels/LauncherPanel.qml');
const dashboard = read('modules/nexus/pages/panels/DashboardPanel.qml');

test('wallpaper limit controls the graph model and queues changes', () => {
    const context = {
        Config: {launcher: {maxWallpapers: 3}},
        Wallpapers: {list: Array.from({length: 40}, (_, i) => ({path: `/wall/${i}`, name: `${i}`}))},
        out: [], idx: {}, wallpaperIndices: [], requests: 0,
        colorFor: () => '', onColorFor: () => '', glyphFor: () => '',
    };
    context.root = context;
    context.requestRebuild = () => context.requests++;
    const limit = graph.match(/readonly property int maxWallpapers: (.+)/)[1];
    const changed = graph.match(/onMaxWallpapersChanged: (.+)/)[1];
    const build = graph.slice(graph.indexOf('        const walls = Wallpapers.list'), graph.indexOf('        // Recent files.'));
    for (const [configured, expected] of [[3, 3], [7, 7], [-2, 1], [90, 30]]) {
        context.Config.launcher.maxWallpapers = configured;
        context.maxWallpapers = runInNewContext(limit, context);
        runInNewContext(changed, context);
        context.out = [];
        runInNewContext(`(function() {${build}})()`, context);
        assert.equal(context.out.length, expected);
        assert.equal(context.wallpaperIndices.length, expected);
    }
    assert.equal(context.requests, 4);
});

test('living dashboard hides unsupported edge gestures and their section', () => {
    const predicate = dashboard.match(/readonly property bool hasEdgeGestures: (.+)/)[1];
    for (const [navStyle, expected] of [['living', false], ['classic', true]])
        assert.equal(runInNewContext(predicate, {Config: {dashboard: {navStyle}}}), expected);
    assert.equal((dashboard.match(/visible: root.hasEdgeGestures/g) ?? []).length, 3);
    assert.match(dashboard, /last: !root.hasEdgeGestures/);
});

test('launcher settings expose active graph controls and supported action matching', () => {
    assert.doesNotMatch(launcher, /launcher\.(showOnHover|dragThreshold|maxShown)|useFuzzy\.(apps|wallpapers|schemes|variants)/);
    assert.match(launcher, /onToggled: GlobalConfig.launcher.useFuzzy.actions = checked/);
    assert.match(launcher, /onMoved: v => GlobalConfig.launcher.maxWallpapers = v/);
    const workspaces = read('modules/nexus/pages/panels/taskbar/BarWorkspaces.qml');
    assert.doesNotMatch(workspaces, /activeTrail/);
});
