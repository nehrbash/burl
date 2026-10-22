import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const { sync } = runInNewContext(readFileSync(new URL('../modules/launcher/GraphModels.js', import.meta.url), 'utf8') + '; ({ sync })');

test('membership changes retain rows by identity and update their simulation indices', () => {
    const rows = [];
    const model = {
        get count() { return rows.length; },
        get: i => rows[i],
        remove: i => rows.splice(i, 1),
        insert: (i, row) => rows.splice(i, 0, row),
        move: (from, to) => rows.splice(to, 0, rows.splice(from, 1)[0]),
        setProperty: (i, key, value) => { rows[i][key] = value; },
    };
    const nodes = ids => ids.map(id => ({ id }));
    sync(model, nodes(['a', 'b', 'c']), [0, 1, 2]);
    const [a, b, c] = rows;
    sync(model, nodes(['c', 'd', 'a']), [0, 1, 2]);
    assert.deepEqual(rows.map(row => row.nodeId), ['c', 'd', 'a']);
    assert.deepEqual(rows.map(row => row.nodeIndex), [0, 1, 2]);
    assert.equal(rows[0], c);
    assert.equal(rows[2], a);
    assert.ok(!rows.includes(b));
    sync(model, nodes(['a', 'c', 'd']), [1, 2]);
    assert.equal(rows[0], c);
    assert.deepEqual(rows.map(row => row.nodeIndex), [1, 2]);
    sync(model, [], [0]);
    assert.equal(rows.length, 0);
});
