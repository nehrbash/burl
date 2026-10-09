import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';
const source = readFileSync(new URL('../services/Weather.qml', import.meta.url), 'utf8');
const match = source.match(/function parseMoonPhase\(daily: var\): real \{([\s\S]*?)\n    \}/);
const parse = runInNewContext(`(function(daily) {${match[1]}})`);
test('weather moon phase preserves new moon and the provider fraction', () => {
    for (const phase of [0, 0.25, 0.366, 0.5, 0.75, 1])
        assert.equal(parse({moon_phase: [phase]}), phase);
});
test('unavailable or malformed astronomy data never masquerades as new moon', () => {
    for (const daily of [null, {}, {moon_phase: []}, ...[null, '0.5', NaN, -0.1, 1.1].map(p => ({moon_phase: [p]}))])
        assert.equal(parse(daily), -1);
});
