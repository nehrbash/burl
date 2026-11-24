import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';
const policy = {};
runInNewContext(readFileSync(new URL('../services/IdlePolicy.js', import.meta.url), 'utf8'), policy);

const plain = value => JSON.parse(JSON.stringify(value));
const monitors = idle => plain(policy.monitors(idle));
const defaults = { lockAfter: 300, screenOffAfter: 600, sleepAfter: 0, sleepAction: 'suspend', timeouts: [] };

test('defaults lock then turn the screen off and never sleep', () => {
    assert.deepEqual(monitors(defaults), [
        { timeout: 300, idleAction: 'lock' },
        { timeout: 600, idleAction: 'dpms off', returnAction: 'dpms on' }
    ]);
});

test('sleep stage uses the configured action', () => {
    const m = monitors({ ...defaults, sleepAfter: 900, sleepAction: 'suspendThenHibernate' });
    assert.deepEqual(m[2], { timeout: 900, idleAction: ['suspendThenHibernate'] });
    assert.deepEqual(monitors({ ...defaults, sleepAfter: 900, sleepAction: 'hibernate' })[2].idleAction, ['hibernate']);
});

test('unknown sleep action falls back to suspend', () => {
    assert.deepEqual(monitors({ ...defaults, sleepAfter: 60, sleepAction: 'poweroff' })[2].idleAction, ['suspend']);
});

test('zero, negative and non-numeric delays disable a stage', () => {
    assert.deepEqual(monitors({ ...defaults, lockAfter: 0, screenOffAfter: -5, sleepAfter: 'x' }), []);
});

test('non-empty legacy timeouts override the stages', () => {
    const legacy = [{ timeout: 10, idleAction: 'lock' }];
    assert.equal(policy.monitors({ ...defaults, sleepAfter: 60, timeouts: legacy }), legacy);
    assert.equal(policy.usesLegacyTimeouts({ timeouts: legacy }), true);
    assert.equal(policy.usesLegacyTimeouts(defaults), false);
});
