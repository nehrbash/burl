import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';
const source = readFileSync(new URL('../modules/launcher/GraphDrift.js', import.meta.url), 'utf8').replace('.pragma library', '');
const offset = runInNewContext(source + '\noffset');
test('idle orbits stay bounded and move continuously in different directions', () => {
    for (const seconds of [0, 10, 100, 1000000]) {
        for (let index = 0; index < 100; index++) {
            const a = offset(seconds, 1, index);
            const b = offset(seconds + 1/30, 1, index);
            assert.ok(Math.hypot(a.x, a.y) <= 8);
            assert.ok(Math.hypot(b.x-a.x, b.y-a.y) < 0.05);
        }
    }
    const velocities = [0, 1, 2, 3].map(i => {
        const a = offset(10, 1, i), b = offset(11, 1, i);
        return [b.x-a.x, b.y-a.y];
    });
    assert.ok(velocities.some(v => v[0] > 0));
    assert.ok(velocities.some(v => v[0] < 0));
    assert.ok(velocities.some(v => v[1] > 0));
    assert.ok(velocities.some(v => v[1] < 0));
});
test('reduced motion removes the orbit', () => {
    const p = offset(250, 0, 8);
    assert.equal(p.x, 0);
    assert.equal(p.y, 0);
});
