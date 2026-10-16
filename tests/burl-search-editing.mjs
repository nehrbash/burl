import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {test} from 'node:test';

const source = readFileSync(new URL('../modules/launcher/SearchEditing.js', import.meta.url), 'utf8');
const editing = runInNewContext(`${source}\n({apply})`);
function field(initial, cursor = initial.length) {
    let text = initial;
    const undo = [];
    return {
        get text() { return text; },
        set text(_) { throw new Error('Whole-text assignment discards editing history'); },
        cursorPosition: cursor, selectionStart: cursor, selectionEnd: cursor,
        remove(start, end) {
            undo.push(text);
            text = text.slice(0, start) + text.slice(end);
        },
        insert(position, inserted) {
            undo.push(text);
            text = text.slice(0, position) + inserted + text.slice(position);
        },
        deselect() { this.selectionStart = this.selectionEnd = this.cursorPosition; },
        select(start, end) { this.selectionStart = start; this.selectionEnd = end; this.cursorPosition = end; },
        undo() { text = undo.pop() ?? text; }
    };
}
const run = (input, command, state = {kill: ''}) => {
    assert.equal(editing.apply(input, command, state), true);
    return input;
};

test('line and character motions leave text intact and clear selection', () => {
    const input = field('one two');
    input.select(0, 3);
    for (const [command, position] of [['C-a', 0], ['C-b', 0], ['C-f', 1], ['C-e', 7], ['C-f', 7], ['C-b', 6]]) {
        run(input, command);
        assert.equal(input.cursorPosition, position);
        assert.equal(input.selectionStart, input.selectionEnd);
        assert.equal(input.text, 'one two');
    }
});

test('word motions skip punctuation and preserve Unicode letter sequences', () => {
    for (const helper of [editing, runInNewContext(`${source}\nwordPattern = null; ({apply})`)]) {
        const input = field('café—東京 next');
        for (const [command, position] of [['M-b', 8], ['M-b', 5], ['M-b', 0], ['M-f', 4], ['M-f', 7], ['M-f', 12]]) {
            assert.equal(helper.apply(input, command, {kill: ''}), true);
            assert.equal(input.cursorPosition, position, command);
        }
    }
});

test('character edits and motions never split an astral character', () => {
    const input = field('a😀b', 1);
    run(input, 'C-f');
    assert.equal(input.cursorPosition, 3);
    run(input, 'C-b');
    assert.equal(input.cursorPosition, 1);
    run(input, 'C-d');
    assert.equal(input.text, 'ab');
    const backward = field('a😀b', 3);
    run(backward, 'C-h');
    assert.equal(backward.text, 'ab');
    assert.equal(backward.cursorPosition, 1);
});

test('kill commands retain the removed range for yank and use undoable edits', () => {
    for (const [command, cursor, remaining, killed] of [
        ['C-k', 4, 'one ', 'two three'], ['C-u', 4, 'two three', 'one '],
        ['C-w', 7, 'one  three', 'two'], ['M-Backspace', 7, 'one  three', 'two'],
        ['M-d', 3, 'one three', ' two']
    ]) {
        const input = field('one two three', cursor);
        const state = {kill: ''};
        run(input, command, state);
        assert.equal(input.text, remaining, command);
        assert.equal(state.kill, killed, command);
        run(input, 'C-y', state);
        assert.equal(input.text, 'one two three', command);
        input.undo();
        assert.equal(input.text, remaining);
        input.undo();
        assert.equal(input.text, 'one two three');
    }
});

test('deletion and yank replace selections in either direction', () => {
    for (const command of ['C-k', 'C-u', 'C-w', 'M-Backspace', 'M-d', 'C-h', 'C-d']) {
        for (const range of [[2, 5], [5, 2]]) {
            const input = field('abcdefg');
            input.select(...range);
            const state = {kill: 'old'};
            run(input, command, state);
            assert.equal(input.text, 'abfg');
            assert.equal(input.cursorPosition, 2);
            assert.equal(state.kill, command === 'C-h' || command === 'C-d' ? 'old' : 'cde');
        }
    }
    const input = field('abcdefg');
    input.select(2, 5);
    run(input, 'C-y', {kill: '東京'});
    assert.equal(input.text, 'ab東京fg');
    assert.equal(input.cursorPosition, 4);
});

test('empty ranges preserve kill text and unknown commands are unhandled', () => {
    const input = field('');
    const state = {kill: 'saved'};
    for (const command of ['C-k', 'C-u', 'C-w', 'M-d', 'C-h', 'C-d']) run(input, command, state);
    assert.equal(state.kill, 'saved');
    assert.equal(input.text, '');
    assert.equal(editing.apply(input, 'C-z', state), false);
    input.select(0, 0);
    run(input, 'C-y', {kill: ''});
    assert.equal(input.text, '');
});
