import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { test } from 'node:test';

test('actual service QML reads status, confirms actions and clears stale data on failure', {skip: process.env.RUN_QML_SERVICES !== '1', timeout: 45000}, async () => {
    const dir = mkdtempSync(join(tmpdir(), 'burl-services-'));
    let paused = false, failed = false;
    const calls = [];
    const server = createServer((req, res) => {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            calls.push([req.method, req.url, body]);
            if (req.headers['x-api-key'] !== 'fixture-secret') { res.writeHead(403); res.end('{}'); return; }
            res.setHeader('Content-Type', 'application/json');
            if (req.url === '/rest/fixture/fail') { failed = true; res.end('{}'); return; }
            if (failed) { res.writeHead(503); res.end('{}'); return; }
            const responses = {
                '/rest/system/status': {myID: 'self'},
                '/rest/system/connections': {connections: {peer: {connected: true, address: '100.2.2.2:22000'}}},
                '/rest/config/devices': [{deviceID: 'self'}, {deviceID: 'peer', name: 'Laptop'}],
                '/rest/config/folders': [{id: 'doc / test', label: 'Notes', path: '/tmp/docs', paused}],
                '/rest/db/status?folder=doc%20%2F%20test': {state: 'idle', globalBytes: 100, needBytes: 0, needTotalItems: 0}
            };
            if (req.method === 'PATCH') { paused = JSON.parse(body).paused; res.end('{}'); return; }
            res.end(JSON.stringify(responses[req.url] || {}));
        });
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    try {
        const root = join(dir, 'quickshell', 'qs');
        mkdirSync(join(root, 'services'), {recursive: true});
        mkdirSync(join(root, 'fixture'));
        mkdirSync(join(dir, 'bin'));
        for (const name of ['Tailscale', 'Syncthing']) {
            writeFileSync(join(root, 'services', name + '.qml'), readFileSync(new URL('../services/' + name + '.qml', import.meta.url), 'utf8').replace('import Burl.Config', 'import qs.fixture'));
        }
        copyFileSync(new URL('../services/ServiceStatus.js', import.meta.url), join(root, 'services', 'ServiceStatus.js'));
        writeFileSync(join(dir, 'config.xml'), '<configuration><gui><apikey>fixture-secret</apikey></gui></configuration>');
        writeFileSync(join(dir, 'bin', 'tailscale'), `#!/bin/sh
case "$1" in
status) printf '%s\\n' '{"BackendState":"Running","TailscaleIPs":["100.1.1.1"],"Peer":{"p":{"HostName":"laptop","Online":true,"ExitNodeOption":true,"TailscaleIPs":["100.2.2.2"]}}}';;
set) printf '%s\\n' "$2" > '${dir}/action';;
esac
`, {mode: 0o755});
        writeFileSync(join(root, 'fixture', 'GlobalConfig.qml'), `pragma Singleton
import QtQuick
QtObject { property QtObject services: QtObject {
property bool tailscaleEnabled: true
property bool syncthingEnabled: true
property string syncthingConfigPath: ${JSON.stringify(join(dir, 'config.xml'))}
property string syncthingUrl: "http://127.0.0.1:${server.address().port}"
} }
`);
        writeFileSync(join(root, 'test.qml'), `import QtQuick
import Quickshell
import qs.services
import qs.fixture
ShellRoot {
    id: root
    property var tailscale: Tailscale
    property var syncthing: Syncthing
    property int step: 0
    property int ticks: 0
    function check(condition, message) { if (!condition) { console.error("ASSERT", message); Qt.quit(); } }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (++root.ticks > 300) { console.error("TIMEOUT", root.step, Syncthing.error); Qt.quit(); }
            if (root.step === 0 && Syncthing.available && Tailscale.connected) {
                root.check(Syncthing.folders.length === 1 && Syncthing.folders[0].state === "Up to date", "folders");
                root.check(Syncthing.connectedCount === 1 && Syncthing.devices.length === 1, "devices exclude self");
                root.check(Tailscale.onlineCount === 1, "peers");
                Tailscale.setExitNode("100.2.2.2");
                Syncthing.pauseFolder(Syncthing.folders[0]);
                root.step = 1;
            } else if (root.step === 1 && !Syncthing.busy && !Syncthing.refreshing && Syncthing.folders[0]?.paused) {
                root.check(Syncthing.summary === "Paused", "paused summary");
                Syncthing.request("GET", "fixture/fail", null, () => Syncthing.refresh());
                root.step = 2;
            } else if (root.step === 2 && Syncthing.error) {
                root.check(!Syncthing.available && !Syncthing.folders.length && !Syncthing.devices.length, "stale data cleared");
                GlobalConfig.services.syncthingEnabled = false;
                root.step = 3;
            } else if (root.step === 3 && !Syncthing.enabled) {
                root.check(Syncthing.summary === "Disabled" && !Syncthing.busy, "disable");
                console.log("SERVICES-PASS"); Qt.quit();
            }
        }
    }
}
`);
        const result = await new Promise(resolve => {
            const child = spawn('quickshell', ['--no-color', '-p', join(root, 'test.qml')], {env: {...process.env, PATH: join(dir, 'bin') + ':' + process.env.PATH, QT_QPA_PLATFORM: 'offscreen', QS_DISABLE_CRASH_HANDLER: '1'}});
            let log = '';
            child.stdout.on('data', c => log += c); child.stderr.on('data', c => log += c);
            const timeout = setTimeout(() => child.kill('SIGKILL'), 35000);
            child.on('close', code => { clearTimeout(timeout); resolve({code, log}); });
        });
        assert.equal(result.code, 0, result.log);
        assert.match(result.log, /SERVICES-PASS/);
        assert.doesNotMatch(result.log, /ASSERT|TypeError|ReferenceError|Unable to assign|TIMEOUT/);
        assert.equal(readFileSync(join(dir, 'action'), 'utf8').trim(), '--exit-node=100.2.2.2');
        assert.ok(calls.some(([method, path, body]) => method === 'PATCH' && path.endsWith('doc%20%2F%20test') && JSON.parse(body).paused));
    } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); rmSync(dir, {recursive:true, force:true}); }
});
