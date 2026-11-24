import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';
const status = {};
runInNewContext(readFileSync(new URL('../services/ServiceStatus.js', import.meta.url), 'utf8'), status);

test('tailnet status distinguishes online peers, direct routes and exit nodes', () => {
    const result = status.tailscale({ BackendState: 'Running', Self: {HostName: 'local'}, TailscaleIPs: ['100.1.1.1'], Peer: {
        a: {HostName: 'offline', Online: false},
        b: {HostName: 'exit', Online: true, ExitNode: true, ExitNodeOption: true, TailscaleIPs: ['100.2.2.2'], Active: true, Relay: 'nyc'},
        c: {HostName: 'direct', Online: true, CurAddr: '10.0.0.1:123'}
    }});
    assert.equal(result.ip, '100.1.1.1');
    assert.equal(result.peers[0].connection, 'Direct');
    assert.equal(result.peers[1].exitNode, true);
    assert.equal(result.peers[1].connection, 'Relay');
    assert.equal(result.peers[2].online, false);
    assert.throws(() => status.tailscale({}));
    assert.equal(status.tailscale({BackendState: 'NeedsLogin', AuthURL: 'file:///tmp/x'}).authUrl, '');
});

test('folder progress handles deletions, errors, pauses and receive-only changes', () => {
    const config = {id: 'docs', path: '/tmp/docs'};
    assert.equal(status.folder(config, {globalBytes: 100, needBytes: 40, needTotalItems: 2}).progress, 0.6);
    assert.equal(status.folder(config, {globalBytes: 100, needBytes: 0, needTotalItems: 1}).state, 'Out of sync');
    assert.equal(status.folder(config, {pullErrors: 1}).state, 'Error');
    assert.equal(status.folder({...config, paused: true}, {error: 'unavailable'}).state, 'Paused');
    assert.equal(status.folder(config, {receiveOnlyTotalItems: 1}).state, 'Local changes');
    assert.equal(status.folder(config, {state: 'scanning'}).state, 'Scanning');
    assert.equal(status.folder(config, {error: 'HTTP 404'}).progress, 0);
});

test('credentials remain restricted to loopback HTTP endpoints', () => {
    for (const url of ['http://127.0.0.1:8384', 'http://localhost', 'http://[::1]:8384']) assert.equal(status.localUrl(url), true);
    for (const url of ['https://example.com', 'http://localhost.evil:8384', 'http://127.0.0.1@evil', 'file:///tmp/key', 'http://localhost/path']) assert.equal(status.localUrl(url), false);
    assert.equal(status.apiKey('<configuration><gui><apikey>test-key_123</apikey></gui></configuration>'), 'test-key_123');
    assert.equal(status.apiKey('<configuration/>'), '');
});

test('incomplete API data cannot become an up-to-date snapshot', () => {
    assert.equal(status.validResponse('config/folders', {}), false);
    assert.equal(status.validResponse('system/status', {}), false);
    assert.equal(status.validResponse('db/status?folder=doc', {}), false);
    assert.equal(status.validResponse('config/folders', [{id:'doc'}]), true);
});

test('syncthing timestamps treat epoch and zero time as never and age relative to now', () => {
    assert.equal(status.timestamp('1969-12-31T19:00:00-05:00'), 0);
    assert.equal(status.timestamp('0001-01-01T00:00:00Z'), 0);
    const now = status.timestamp('2026-11-24T12:00:00Z');
    assert.equal(status.ago(0, now), '');
    assert.equal(status.ago(now - 30e3, now), 'just now');
    assert.equal(status.ago(now - 5 * 60e3, now), '5m ago');
    assert.equal(status.ago(now - 3 * 3600e3, now), '3h ago');
    assert.equal(status.ago(now - 49 * 3600e3, now), '2d ago');
});

test('syncthing peers report last seen and remote completion', () => {
    const offline = status.peer({deviceID: 'a', name: 'Laptop'}, {connected: false, address: 'x'}, {lastSeen: '2026-11-24T09:00:00-05:00'}, {completion: 92.5, needItems: 3, needDeletes: 1});
    assert.equal(offline.connected, false);
    assert.equal(offline.address, '');
    assert.equal(offline.lastSeen, Date.parse('2026-11-24T14:00:00Z'));
    assert.equal(offline.completion, 92.5);
    assert.equal(offline.needed, 4);
    const unknown = status.peer({deviceID: 'b'}, undefined, {lastSeen: '1970-01-01T00:00:00Z'}, null);
    assert.equal(unknown.lastSeen, 0);
    assert.equal(unknown.completion, -1);
    assert.equal(status.folder({id: 'doc'}, {state: 'idle'}, {lastScan: '2026-11-24T14:00:00Z', lastFile: {at: '0001-01-01T00:00:00Z'}}).lastChange, 0);
    assert.equal(status.validResponse('db/completion?device=a', {}), false);
});
