import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {test} from 'node:test';

const {apply} = runInNewContext(readFileSync(new URL('../services/BluetoothStartupPolicy.js', import.meta.url), 'utf8') + '\n({apply})');

test('startup enables adapters once and respects a subsequent manual off', () => {
    const adapter = {enabled: false};
    let seen = apply([adapter], [], true);
    assert.equal(adapter.enabled, true);
    adapter.enabled = false;
    seen = apply([adapter], seen, true);
    assert.equal(adapter.enabled, false);
    const added = {enabled: false};
    apply([adapter, added], seen, true);
    assert.equal(adapter.enabled, false);
    assert.equal(added.enabled, true);
});

test('disabled preference leaves power unchanged and enabling preference applies immediately', () => {
    const off = {enabled: false};
    const on = {enabled: true};
    apply([off, on], [], false);
    assert.equal(off.enabled, false);
    assert.equal(on.enabled, true);
    apply([off, on], [], true);
    assert.equal(off.enabled, true);
});

test('late adapters and adapters returning after removal receive startup policy', () => {
    const adapter = {enabled: false};
    let seen = apply([], [], true);
    seen = apply([adapter], seen, true);
    assert.equal(adapter.enabled, true);
    seen = apply([], seen, true);
    adapter.enabled = false;
    apply([adapter], seen, true);
    assert.equal(adapter.enabled, true);
});
