import assert from 'node:assert/strict';
import {after, test} from 'node:test';
import {mkdtempSync, mkdirSync, writeFileSync, symlinkSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const command = fileURLToPath(new URL('../bin/burl-file-search', import.meta.url));
const root = mkdtempSync(join(tmpdir(), 'burl-file-search-'));
after(() => rmSync(root, {recursive: true, force: true}));
function file(name) {
    const path = join(root, name);
    mkdirSync(join(path, '..'), {recursive: true});
    writeFileSync(path, 'fixture');
    return path;
}
const alpha = file('Documents/Alpha Notes.org');
file('Documents/alpha TODO.txt');
file('Documents/École plan.txt');
file('Documents/[abc] literal.txt');
file('Documents/.alpha-private');
file('.cache/alpha.org');
file('node_modules/alpha.js');
file('build/alpha.o');
const outside = mkdtempSync(join(tmpdir(), 'burl-file-search-outside-'));
after(() => rmSync(outside, {recursive: true, force: true}));
writeFileSync(join(outside, 'alpha-external.org'), 'outside');
symlinkSync(outside, join(root, 'linked-directory'));
symlinkSync(alpha, join(root, 'alpha-symlink.org'));

function search(args, options = {}) {
    const result = spawnSync('guile', ['-s', command, ...args], {
        encoding: 'utf8', timeout: 10000,
        env: {...process.env, HOME: root, GUILE_AUTO_COMPILE: '0'}, ...options
    });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
}
const names = result => result.entries.map(entry => entry.label).sort();

test('file lookup requires three nonspace characters and defaults to home', () => {
    for (const query of ['', 'a b', 're:ab']) {
        const result = search(['--query', query]);
        assert.deepEqual(result.entries, []);
        assert.equal(result.scanned, 0);
    }
    assert.deepEqual(names(search(['--query', 'alpha'])), ['Alpha Notes.org', 'alpha TODO.txt']);
});

test('literal words match paths case-insensitively with spaces and unicode', () => {
    const result = search(['--root', root, '--query', 'NOTES documents']);
    assert.deepEqual(result.entries, [{path: alpha, label: 'Alpha Notes.org', queries: ['NOTES documents']}]);
    assert.deepEqual(names(search(['--query', 'éCOLE plan'])), ['École plan.txt']);
    assert.deepEqual(names(search(['--query', '[abc]'])), ['[abc] literal.txt']);
    assert.deepEqual(search(['--query', 'alpha nonexistent']).entries, []);
});

test('repeated queries are a union with exact query membership on each result', () => {
    const result = search(['--query', 'alpha', '--query', 'notes', '--query', 'école']);
    assert.equal(result.entries.length, 3);
    assert.deepEqual(result.entries.find(entry => entry.path === alpha).queries, ['alpha', 'notes']);
    assert.deepEqual(result.entries.find(entry => entry.label === 'École plan.txt').queries, ['école']);
});

test('explicit regular expressions support alternation, anchors, delimiters and escaped slashes', () => {
    for (const query of ['re:notes\\.org$', 're:/notes\\.org$/', 're:/Documents\\/Alpha Notes/', 're:/Documents[/]Alpha Notes/'])
        assert.deepEqual(names(search(['--query', query])), ['Alpha Notes.org'], query);
    assert.deepEqual(names(search(['--query', 're:(notes|todo)\\.(org|txt)$'])), ['Alpha Notes.org', 'alpha TODO.txt']);
    const absolute = `re:^${root}/Documents/Alpha Notes`;
    assert.deepEqual(names(search(['--query', absolute])), ['Alpha Notes.org']);
});

test('invalid regex, delimiters, roots and arguments return structured errors', () => {
    for (const args of [
        ['--query', 're:[ab'], ['--query', 're:['], ['--query', 're:/unclosed'], ['--query', 're:/alpha/i'],
        ['--query', 'alpha', '--root', join(root, 'missing')], ['--limit', '0'], ['--unknown']
    ]) {
        const result = search(args);
        assert.deepEqual(result.entries, []);
        assert.ok(result.error.length > 0, args.join(' '));
    }
});

test('limits bound both matches and entries examined', () => {
    const limited = search(['--query', 'alpha', '--limit', '1']);
    assert.equal(limited.entries.length, 1);
    assert.equal(limited.truncated, true);
    const budgeted = search(['--query', 'not-present', '--budget', '2']);
    assert.equal(budgeted.scanned, 2);
    assert.equal(budgeted.truncated, true);
    for (let i = 0; i < 65; ++i) file(`limits/limit-${i}.txt`);
    const capped = search(['--root', join(root, 'limits'), '--query', 'limit', '--limit', '999']);
    assert.equal(capped.entries.length, 60);
    assert.equal(capped.truncated, true);
});

test('hidden files, build caches and directory symlinks are excluded', () => {
    const result = search(['--query', 'alpha']);
    assert.deepEqual(names(result), ['Alpha Notes.org', 'alpha TODO.txt']);
    assert.equal(result.truncated, false);
});


test('elapsed time stops a scan before exhausting a large directory', () => {
    for (let i = 0; i < 1500; ++i) file(`deadline/item-${i}.txt`);
    const result = search(['--root', join(root, 'deadline'), '--query', 'not-present', '--timeout-ms', '1']);
    assert.equal(result.truncated, true);
    assert.ok(result.scanned < 1502);
    assert.equal(result.error, '');
});


test('bounded searches cover sibling directories before descending into a large subtree', () => {
    file('breadth/needle-root.txt');
    for (const branch of ['one', 'two']) {
        file(`breadth/${branch}/needle-${branch}.txt`);
        file(`breadth/${branch}/deep/needle-deep-${branch}.txt`);
    }
    const result = search(['--root', join(root, 'breadth'), '--query', 'needle', '--limit', '3']);
    assert.deepEqual(names(result), ['needle-one.txt', 'needle-root.txt', 'needle-two.txt']);
    assert.equal(result.truncated, true);
});
