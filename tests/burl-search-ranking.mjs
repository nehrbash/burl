import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const source = readFileSync(new URL('../modules/launcher/SearchRanking.js', import.meta.url), 'utf8').replace('.pragma library', '');
const { score } = runInNewContext(source + '\n({score})');

test('exact, prefix, word, substring and subsequence results have predictable priority', () => {
    const names = ['Steam', 'Steam Runtime', 'Launch Steam', 'MySteam', 'System Team'];
    const scores = names.map(name => score(name, 'steam'));
    for (let i = 1; i < scores.length; ++i)
        assert.ok(scores[i - 1] > scores[i], `${names[i - 1]} should outrank ${names[i]}`);
    assert.ok(scores.at(-1) > 0);
});

test('all query words must match and may appear in any order', () => {
    assert.ok(score('GNU Emacs Editor', 'editor emacs') > 0);
    assert.equal(score('GNU Emacs Editor', 'editor steam'), 0);
    assert.ok(score('Visual Studio Code', 'visual code') > score('Versioned Source Catalog', 'visual code'));
});

test('single edit typos work for long words but missing arbitrary letters do not', () => {
    for (const query of ['staem', 'steamm', 'stean', 'setam']) {
        assert.ok(score('Steam', query) > 0, query);
        assert.ok(score(query, query) > score('Steam', query));
    }
    assert.equal(score('Steam', 'stxxam'), 0);
    assert.equal(score('Steam', 'sxe'), 0);
    assert.equal(score('Steam', 'xyz'), 0);
});

test('metadata can discover apps but stays below even fuzzy title matches', () => {
    assert.ok(score('Firefox', 'browser', ['Web Browser']) > 0);
    assert.ok(score('Browser', 'browser') > score('Firefox', 'browser', ['Web Browser']));
    assert.ok(score('System Team', 'steam') > score('Other', 'steam', ['Steam']));
    assert.equal(score('Other', 'staem', ['Steam']), 0);
    assert.ok(score('Firefox', 'firefox browser', ['Web Browser']) > 0);
});

test('normalization handles accents, case and whitespace', () => {
    assert.equal(score('Café Editor', '  CAFE   editor '), score('Cafe Editor', 'cafe editor'));
    assert.equal(score('', ''), 0);
    assert.equal(score(null, 'steam'), 0);
    assert.ok(Number.isFinite(score('Steam', 's')));
});

test('a later compact subsequence outranks an earlier sparse one', () => {
    assert.ok(score('s unusual t unusual m stm', 'stm') > score('s unusual t unusual m', 'stm'));
});

test('an empty graph clears stale results and navigation selection', () => {
    const graph = readFileSync(new URL('../modules/launcher/GraphView.qml', import.meta.url), 'utf8');
    const match = graph.match(/^    function rescore\(\): void \{([\s\S]*?)\n    \}/m);
    assert.ok(match);
    const state = { nodes: [], nodeScores: [100], matchIndices: [0], depthToMatch: [0],
        currentMatchIndex: 1, currentNode: 0, hoverIndex: 0, navigationHistory: [0],
        browsing: true, _assignNavSlots() { state.slotsCleared = state.currentNode === -1; } };
    runInNewContext(`(function() {${match[1]}}).call(this)`, state);
    for (const key of ['nodeScores', 'matchIndices', 'depthToMatch', 'navigationHistory'])
        assert.equal(state[key].length, 0, key);
    assert.equal(state.currentNode, -1);
    assert.equal(state.hoverIndex, -1);
    assert.equal(state.browsing, false);
    assert.equal(state.slotsCleared, true);
});
