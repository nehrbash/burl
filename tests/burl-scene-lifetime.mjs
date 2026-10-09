import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const source = readFileSync(new URL('../modules/launcher/Wrapper.qml', import.meta.url), 'utf8');
const active = source.match(/^        active: (.*)/m)[1];
const preload = source.match(/^        running: (.*)/m)[1];

test('scene retention respects visibility and Performance mode', () => {
    for (const enabled of [false, true]) {
        for (const shouldBeActive of [false, true]) {
            for (const offsetScale of [0, 0.5, 1]) {
                const root = { loaderActive: true, shouldBeActive, offsetScale };
                const retained = runInNewContext(active, { root, GameMode: { enabled } });
                assert.equal(retained, !enabled || shouldBeActive || offsetScale < 1);
            }
        }
    }
    const root = { loaderActive: false, screen: { name: 'test' } };
    const Hypr = { focusedMonitor: { name: 'test' } };
    assert.equal(runInNewContext(preload, { root, Hypr, GameMode: { enabled: true } }), false);
    assert.equal(runInNewContext(preload, { root, Hypr, GameMode: { enabled: false } }), true);
});

test('native Loader destroys closed Performance scenes and retains normal scenes', { skip: !process.env.QMLTESTRUNNER }, () => {
    const dir = mkdtempSync(join(tmpdir(), 'burl-scene-lifetime-'));
    const handler = source.match(/    onShouldBeActiveChanged: \{([\s\S]*?)\n    \}/)[1];
    const triggered = source.match(/onTriggered: root.loaderActive = true/)[0];
    const qml = `import QtQuick
import QtTest
Item {
    id: root
    property bool shouldBeActive: false
    property bool loaderActive: false
    property bool refreshPending: false
    property real offsetScale: 1
    property var screen: ({name: "test"})
    property int created: 0
    property int destroyed: 0
    function reloadWhenReady() {}
    QtObject { id: mode; property bool enabled: true }
    QtObject { id: hypr; property var focusedMonitor: ({name: "test"}) }
    onShouldBeActiveChanged: { ${handler} }
    Timer {
        id: preloadTimer
        interval: 40
        repeat: false
        running: ${preload.replaceAll('GameMode', 'mode').replaceAll('Hypr', 'hypr')}
        ${triggered}
    }
    Loader {
        id: sceneLoader
        active: ${active.replaceAll('GameMode', 'mode')}
        asynchronous: true
        sourceComponent: Item {
            Component.onCompleted: root.created++
            Component.onDestruction: root.destroyed++
        }
    }
    TestCase {
        name: "SceneLifetime"
        function test_lifecycle() {
            wait(80);
            compare(root.created, 0);
            root.shouldBeActive = true;
            tryCompare(root, "created", 1);
            verify(sceneLoader.item !== null);
            root.offsetScale = 0;
            mode.enabled = false;
            mode.enabled = true;
            compare(root.destroyed, 0);
            root.shouldBeActive = false;
            root.offsetScale = 0.5;
            wait(30);
            compare(root.destroyed, 0);
            root.offsetScale = 1;
            tryCompare(root, "destroyed", 1);
            compare(sceneLoader.item, null);
            wait(80);
            compare(root.created, 1);
            root.shouldBeActive = true;
            tryCompare(root, "created", 2);
            mode.enabled = false;
            root.shouldBeActive = false;
            tryCompare(root, "offsetScale", 1);
            wait(30);
            compare(root.destroyed, 1);
            const warm = sceneLoader.item;
            root.shouldBeActive = true;
            compare(sceneLoader.item, warm);
            root.shouldBeActive = false;
            mode.enabled = true;
            tryCompare(root, "destroyed", 2);
            mode.enabled = false;
            tryCompare(root, "created", 3);
            root.loaderActive = false;
            tryCompare(root, "destroyed", 3);
            tryCompare(root, "created", 4);
        }
    }
}`;
    try {
        writeFileSync(join(dir, 'tst_lifetime.qml'), qml);
        const result = spawnSync(process.env.QMLTESTRUNNER, ['-input', dir], {
            encoding: 'utf8', timeout: 15000,
            env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QSG_RHI_BACKEND: 'software' },
        });
        assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
});
