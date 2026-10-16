import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {test} from 'node:test';

const search = runInNewContext(`${readFileSync(new URL('../modules/launcher/SearchQuery.js', import.meta.url), 'utf8')}\n({parse, complete, nodeVisible, matchesSegment, categoryKeyword})`);
const game = {kind: 'app', label: 'Chess', entry: {categories: ['Game', 'BoardGame']}};
const editor = {kind: 'app', label: 'Editor', entry: {categories: 'Utility;TextEditor;'}};
const visible = (node, preferences, query = '', pivot = '') => search.nodeVisible(node, search.parse(query, '>'), preferences, pivot);

test('visibility defaults preserve sources and free text cannot reveal an opted-in source', () => {
    assert.equal(visible(game, []), true);
    assert.equal(visible(game, ['apps']), false);
    assert.equal(visible(game, ['apps'], 'Chess'), false);
    assert.equal(visible(game, ['apps'], '>roam Chess'), false);
    assert.equal(visible(game, ['apps'], '>apps Chess'), true);
    assert.equal(visible(game, ['apps'], '>roam|apps'), true);
    assert.equal(visible(game, ['apps'], '', 'app'), true);
    assert.equal(visible(game, ['unknown']), true);
});

test('category policy keeps hubs discoverable and requires an explicit matching category', () => {
    const preferences = ['category:game'];
    assert.equal(visible(game, preferences), false);
    assert.equal(visible(editor, preferences), true);
    assert.equal(visible({kind: 'category', label: 'Game'}, preferences), true);
    assert.equal(visible(game, preferences, '>apps'), false);
    assert.equal(visible(game, preferences, '', 'app'), false);
    assert.equal(visible(game, preferences, '>apps:Utility'), false);
    assert.equal(visible(game, preferences, '>games'), true);
    assert.equal(visible(game, ['apps', ...preferences], '>games'), true);
    assert.equal(visible(game, ['category:game', 'category:boardgame'], '>games'), true);
    assert.equal(visible(game, preferences, '>apps:BoardGame'), true);
});

test('category selectors accept aliases, unions, suffix placement and configured prefixes', () => {
    for (const scope of ['games', 'game', 'apps:Game', 'app:Game', 'category:Game', 'categories:Game']) {
        const segments = search.parse(`chess >${scope}`, '>');
        assert.equal(segments.length, ['games', 'game'].includes(scope) ? 3 : 2, scope);
        assert.equal(segments[0].q, 'chess');
        assert.equal(search.matchesSegment(game, segments[0]), true);
        assert.equal(search.matchesSegment(editor, segments[0]), false);
    }
    const segments = search.parse('::apps:Game|roam chess', '::');
    assert.equal(segments.length, 3);
    assert.equal(search.complete('>apps:Game', '>'), '>apps:Game ');
    assert.equal(search.categoryKeyword('Game'), 'games');
    assert.equal(search.categoryKeyword('Utility'), 'apps:Utility');
    assert.equal(visible({...game, entry: {categories: 'Game BoardGame'}}, ['category:game'], '>games'), true);
    assert.equal(visible({...game, entry: {categories: 'NotGame'}}, ['category:game']), true);
});

const graph = readFileSync(new URL('../modules/launcher/GraphView.qml', import.meta.url), 'utf8');
const method = name => graph.match(new RegExp(`^    function ${name}\\(\\): void \\{([\\s\\S]*?)\\n    \\}`, 'm'))[1];

test('search applies pending policy before scoring, including immediate activation after timer stopped', () => {
    const events = [];
    const state = {
        visibilityPolicyKey: 'games', appliedVisibilityPolicyKey: 'general', rebuildPending: true,
        filterTimer: {running: false, stop() { events.push('stop'); }},
        rebuild() { events.push('rebuild'); state.appliedVisibilityPolicyKey = state.visibilityPolicyKey; },
        rescore() { events.push('score'); }, sim: {reheat() {}}, fitCamera() {}, edgeLayer: {refresh() {}}
    };
    state._applyFilter = () => runInNewContext(method('_applyFilter'), state);
    runInNewContext(`(function(){${method('flushSearch')}})()`, state);
    assert.deepEqual(events, ['stop', 'rebuild', 'score']);
    assert.equal(state.rebuildPending, false);
    events.length = 0;
    runInNewContext(`(function(){${method('flushSearch')}})()`, state);
    assert.deepEqual(events, []);
});

test('filtered candidates own all delegate indices and category edges use the retained entry', () => {
    const start = graph.indexOf('        const idx = {};', graph.indexOf('out = out.filter'));
    const end = graph.indexOf('        // Skip the reassignment', start);
    const state = {out: [{id: 'wall', kind: 'wallpaper'}, {id: 'game', kind: 'app'},
        {id: 'track', kind: 'spotifyTrack', imageUrl: 'cover'}], appIndices: [0, 1], wallpaperIndices: [2], coverImageIndices: [3]};
    runInNewContext(graph.slice(start, end), state);
    assert.deepEqual(Array.from(state.appIndices), [1]);
    assert.deepEqual(Array.from(state.wallpaperIndices), [0]);
    assert.deepEqual(Array.from(state.coverImageIndices), [2]);
    assert.doesNotMatch(graph, /Apps\.list[^\n]*appIndices\.indexOf/);
});

 test('Steam participates in game filters and shares category visibility rules', () => {
    const steam = {kind: 'steam', source: {appId: '570'}};
    assert.equal(visible(steam, ['category:game']), false);
    assert.equal(visible(steam, ['category:game'], '>steam'), true);
    assert.equal(visible(steam, ['steam'], '>games'), true);
    assert.equal(visible(steam, ['category:game'], '>apps'), false);
    assert.equal(visible(steam, ['steam'], '>apps:Game'), false);
    const segments = search.parse('>games chess', '>');
    assert.equal(segments.some(segment => search.matchesSegment(steam, segment)), true);
});
