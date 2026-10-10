import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {test} from 'node:test';

const parser = runInNewContext(`${readFileSync(new URL('../modules/launcher/SearchQuery.js', import.meta.url), 'utf8')}\n({parse, complete})`);
const parse = (text, prefix = '>') => JSON.parse(JSON.stringify(parser.parse(text, prefix)));
const segment = (kind, q = '') => ({kind, q});

test('filters before and after the query are equivalent with singular and plural aliases', () => {
    for (const text of ['steam >app', '>app steam', '>apps steam', 'steam >apps', 'steam\t>APP'])
        assert.deepEqual(parse(text), [segment('app', 'steam')]);
    assert.deepEqual(parse('steam >app deck'), [segment('app', 'steam deck')]);
});

test('pipe alternatives share a query and bundled scopes deduplicate kinds', () => {
    for (const text of ['steam >app|roam', '>app|roam steam', '>apps | roam steam'])
        assert.deepEqual(parse(text), [segment('app', 'steam'), segment('roam', 'steam')]);
    assert.deepEqual(parse('>app|apps|roam'), [segment('app'), segment('roam')]);
    assert.deepEqual(parse('>web|tabs docs'), ['webBookmark', 'webFolder', 'webHistory', 'webTab'].map(kind => segment(kind, 'docs')));
});

test('separate scope segments retain independent queries and share leading text', () => {
    assert.deepEqual(parse('>apps steam >recent notes'), [segment('app', 'steam'), segment('recent', 'notes')]);
    assert.deepEqual(parse('notes >app editor >roam project'), [segment('app', 'notes editor'), segment('roam', 'notes project')]);
    assert.deepEqual(parse('>app steam >app firefox'), [segment('app', 'steam'), segment('app', 'firefox')]);
    assert.deepEqual(parse('>wallpaper >apps'), [segment('wallpaper'), segment('app')]);
});

test('unknown commands and embedded markers are not mistaken for filters', () => {
    for (const text of ['steam', '>', '>shutdown', '>shutdown >app', 'steam>app', 'https://host/>app', 'steam >apple', '>app|unknown', '?steam >app', 'steam >constructor'])
        assert.equal(parse(text), null, text);
    assert.deepEqual(parse('>app steam >unknown'), [segment('app', 'steam >unknown')]);
    assert.deepEqual(parse('steam ::app|roam', '::'), [segment('app', 'steam'), segment('roam', 'steam')]);
    assert.equal(parse('steam', ''), null);
});

test('completion supports suffix filters, unions, aliases and custom prefixes', () => {
    for (const [before, after] of [
        ['steam >ap', 'steam >apps '], ['>app', '>app '], ['>app|ro', '>app|roam '],
        ['steam >app | ro', 'steam >app | roam '], ['>web', '>web '], ['>w', '>w'],
        ['>webf', '>webfolder '], ['>app|webh', '>app|webhist ']]) {
        assert.equal(parser.complete(before, '>'), before === after ? null : after);
    }
    for (const text of ['steam>ap', '>app steam', '>app ', '>unknown|ro', '?steam >ap'])
        assert.equal(parser.complete(text, '>'), null, text);
    assert.equal(parser.complete('steam ::ro', '::'), 'steam ::roam ');
});

const emojiSource = readFileSync(new URL('../services/Emoji.qml', import.meta.url), 'utf8');
const scoreEmoji = runInNewContext(`(function(root) {${emojiSource.split('    function rescore(): void {')[1].split('\n    function copy(')[0].replace(/\n    }\s*$/, '')}})`);
const emojis = queries => {
    const root = {
        queries, loaded: true, maxMatches: 40,
        entries: ['certificate', 'cat smiling', 'dog smiling', 'black cat', 'red heart'].map(keywords => ({keywords}))
    };
    scoreEmoji(root);
    return Array.from(root.matches, entry => entry.keywords);
};

test('emoji candidates include every OR branch and all words of a branch', () => {
    assert.deepEqual(emojis(['cat', 'dog']), ['cat smiling', 'dog smiling', 'black cat', 'certificate']);
    assert.deepEqual(emojis(['smiling cat', 'heart red']), ['cat smiling', 'red heart']);
    assert.deepEqual(emojis(['cat', 'cat']), ['cat smiling', 'black cat', 'certificate']);
    assert.equal(emojis(['']).length, 5);
    assert.equal(emojis([]).length, 5);
});
