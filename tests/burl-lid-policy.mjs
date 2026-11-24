import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';
const policy = {};
runInNewContext(readFileSync(new URL('../services/LidPolicy.js', import.meta.url), 'utf8'), policy);

const plain = value => JSON.parse(JSON.stringify(value));
const defaults = { action: 'sleep', actionOnPower: 'sleep', actionDocked: 'nothing' };
const pick = (lid, onBattery, docked) => policy.actionFor(lid, { onBattery, docked });

test('defaults sleep on battery and power, nothing when docked', () => {
    assert.equal(pick(defaults, true, false), 'sleep');
    assert.equal(pick(defaults, false, false), 'sleep');
    assert.equal(pick(defaults, true, true), 'nothing');
    assert.equal(pick(defaults, false, true), 'nothing');
});

test('battery and power actions are independent', () => {
    const lid = { ...defaults, action: 'lock', actionOnPower: 'screenOff' };
    assert.equal(pick(lid, true, false), 'lock');
    assert.equal(pick(lid, false, false), 'screenOff');
});

test('docked action overrides the power source', () => {
    assert.equal(pick({ ...defaults, actionDocked: 'lock' }, true, true), 'lock');
});

test('unknown or missing actions fall back to the per-slot default', () => {
    assert.equal(pick({ action: 'poweroff' }, true, false), 'sleep');
    assert.equal(pick({}, false, false), 'sleep');
    assert.equal(pick({ actionDocked: 'bogus' }, true, true), 'nothing');
});

test('only external outputs count as docked', () => {
    assert.equal(policy.docked(['eDP-1']), false);
    assert.equal(policy.docked(['LVDS-1', 'DSI-1']), false);
    assert.equal(policy.docked(['eDP-1', 'DP-3']), true);
    assert.equal(policy.docked(['HDMI-A-1']), true);
    assert.equal(policy.docked([]), false);
    assert.equal(policy.docked(undefined), false);
});

test('sleep locks first when lockBeforeSleep is set', () => {
    const idle = { lockBeforeSleep: true, sleepAction: 'hibernate' };
    assert.deepEqual(plain(policy.closeSteps('sleep', idle)), ['lock', ['hibernate']]);
    assert.deepEqual(plain(policy.closeSteps('sleep', { ...idle, lockBeforeSleep: false })), [['hibernate']]);
});

test('lock, screenOff and nothing map to their steps', () => {
    const idle = { lockBeforeSleep: true, sleepAction: 'suspend' };
    assert.deepEqual(plain(policy.closeSteps('lock', idle)), ['lock']);
    assert.deepEqual(plain(policy.closeSteps('screenOff', idle)), ['dpms off']);
    assert.deepEqual(plain(policy.closeSteps('nothing', idle)), []);
});

test('only a lid-driven screen off is undone on open', () => {
    assert.deepEqual(plain(policy.openSteps('screenOff')), ['dpms on']);
    for (const performed of ['sleep', 'lock', 'nothing', ''])
        assert.deepEqual(plain(policy.openSteps(performed)), []);
});
