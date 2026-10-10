import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {test} from 'node:test';

function helper(path, names, context = {}) {
    const source = readFileSync(new URL(path, import.meta.url), 'utf8').replace(/^\.(?:pragma|import).*$/gm, '');
    return runInNewContext(source + `\n({${names}})`, context);
}
const args = helper('../modules/launcher/services/CommandArguments.js', 'parseArguments,formatArguments,keywordFor,validKeyword,supportsArguments,aliasesFor,executableFor,invocation,isSessionShorthand');
const ranking = helper('../modules/launcher/SearchRanking.js', 'normalize,score');
const search = helper('../modules/launcher/services/ActionSearch.js', 'query', {Arguments: args, Ranking: ranking});
const plain = value => JSON.parse(JSON.stringify(value));
const editor = {name: 'Text editor', keyword: 'editor', description: 'Edit notes and configuration', command: ['emacsclient', '-n'], acceptArgs: true};

test('argument parsing handles quotes, escaped spaces and empty values without expansion', () => {
    const parsed = args.parseArguments('"file with spaces" --flag \'\' path\\ with\\ spaces "$HOME" "$(touch nope)" a;b');
    assert.deepEqual(plain(parsed), {args: ['file with spaces', '--flag', '', 'path with spaces', '$HOME', '$(touch nope)', 'a;b'], error: ''});
    assert.deepEqual(plain(args.parseArguments('"\\.org$"')), {args: ['\\.org$'], error: ''});
});

test('formatted arguments round trip unicode, quotes, newlines and shell punctuation', () => {
    const values = ['plain', '', 'école notes', "can't", '"quoted"', 'back\\slash', '$HOME;$(date)', 'line\nbreak'];
    assert.deepEqual(plain(args.parseArguments(args.formatArguments(values))).args, values);
});

test('only exact keywords or executable aliases append opted-in arguments', () => {
    assert.deepEqual(plain(args.invocation(editor, 'editor "file with spaces" --flag')), {command: ['emacsclient', '-n', 'file with spaces', '--flag'], error: ''});
    assert.deepEqual(plain(args.invocation(editor, 'emacsclient notes.org')).command, ['emacsclient', '-n', 'notes.org']);
    assert.deepEqual(plain(args.invocation(editor, 'edit notes')).command, ['emacsclient', '-n']);
    assert.ok(args.invocation({...editor, acceptArgs: false}, 'editor notes.org').error);
    assert.ok(args.invocation(editor, 'editor "unfinished').error.includes('quote'));
    assert.ok(args.invocation(editor, 'editor trailing\\').error.includes('backslash'));
    for (const command of [[], '', 'echo', [''], ['   \t'], ['echo', null]])
        assert.ok(args.invocation({...editor, command}, 'editor').error);
});

test('internal action verbs preserve their fixed arguments', () => {
    for (const verb of ['autocomplete', 'setText', 'setMode']) {
        const action = {...editor, command: [verb, 'value']};
        assert.equal(args.supportsArguments(action), false);
        assert.ok(args.invocation(action, 'editor extra').error);
        assert.deepEqual(plain(args.invocation(action, 'editor')).command, [verb, 'value']);
    }
});

test('keyword fallback preserves display names and exact commands rank above descriptions', () => {
    const shutdown = {name: 'Shutdown', description: 'Shutdown the system', command: ['poweroff'], dangerous: true};
    assert.equal(args.keywordFor({name: 'Web search', command: ['setText', '? ']}), 'web-search');
    assert.equal(args.validKeyword('editor-notes'), true);
    assert.equal(args.validKeyword('editor notes'), false);
    assert.equal(search.query([editor, shutdown], 'poweroff', true)[0], shutdown);
    assert.equal(search.query([shutdown, editor], 'editor "notes', true)[0], editor);
    assert.equal(search.query([shutdown, editor], 'configuration', false)[0], editor);
    assert.equal(search.query([editor], 'edtr', false).length, 0);
    assert.equal(search.query([editor], 'edtr', true)[0], editor);
});

const qml = readFileSync(new URL('../modules/launcher/services/Actions.qml', import.meta.url), 'utf8');
function activation(action, text, overrides = {}) {
    const visibility = {launcher: true, dashboard: true};
    const field = {text};
    const calls = [];
    const context = {
        modelData: action, CommandArguments: args,
        GlobalConfig: {launcher: {actionPrefix: '>'}},
        Toaster: {toast: (...message) => calls.push(['toast', ...message])},
        Colours: {setMode: mode => calls.push(['mode', mode])},
        IdleInhibitor: {execSessionAction: argv => {calls.push(['session', ...argv]); return false;}},
        Quickshell: {execDetached: argv => calls.push(['exec', ...argv])}, qsTr: text => text,
        ...overrides
    };
    const match = qml.match(/^        function activate\([^)]*\): void \{([\s\S]*?)\n        \}/m);
    assert.ok(match);
    runInNewContext(`(function(searchField, visibilities) {${match[1]}})`, context)(field, visibility);
    return {field, visibility, calls};
}

test('runtime rejects incomplete arguments and preserves the visible launcher', () => {
    const result = activation(editor, '>editor "unfinished');
    assert.equal(result.calls.length, 1);
    assert.equal(result.calls[0][0], 'toast');
    assert.equal(result.visibility.launcher, true);
    assert.equal(result.visibility.dashboard, true);
});

test('runtime uses argv and preserves session handling and built-in actions', () => {
    const launch = activation(editor, '>editor "literal $(date)"');
    assert.deepEqual(plain(launch.calls), [['exec', 'emacsclient', '-n', 'literal $(date)']]);
    assert.equal(launch.visibility.launcher, false);
    assert.equal(launch.visibility.dashboard, false);
    const session = activation({name: 'Shutdown', command: ['poweroff']}, '>poweroff', {IdleInhibitor: {execSessionAction: () => true}});
    assert.deepEqual(session.calls, []);
    const complete = activation({name: 'Calculator', command: ['autocomplete', 'calc']}, '>calc');
    assert.equal(complete.field.text, '>calc ');
    assert.equal(complete.visibility.launcher, true);
    const mode = activation({name: 'Light', command: ['setMode', 'light']}, '>light');
    assert.deepEqual(mode.calls, [['mode', 'light']]);
    const text = activation({name: 'Web search', command: ['setText', '? ']}, '>web-search');
    assert.equal(text.field.text, '? ');
});

test('runtime launch errors keep the overlay open and dangerous actions stay filtered', () => {
    const failed = activation(editor, '>editor', {Quickshell: {execDetached() {throw new Error('fixture failure');}}});
    assert.equal(failed.visibility.launcher, true);
    assert.equal(failed.calls.at(-1)[0], 'toast');
    const model = qml.match(/^        model: (.*)$/m)[1];
    const safe = {name: 'safe'}, disabled = {name: 'disabled', enabled: false}, dangerous = {name: 'dangerous', dangerous: true};
    const GlobalConfig = {launcher: {actions: [safe, disabled, dangerous], enableDangerousActions: false}};
    assert.deepEqual(Array.from(runInNewContext(model, {GlobalConfig})), [safe]);
    GlobalConfig.launcher.enableDangerousActions = true;
    assert.deepEqual(Array.from(runInNewContext(model, {GlobalConfig})), [safe, dangerous]);
});

test('session aliases never swallow optional or configured arguments', () => {
    const sessionCalls = [];
    const overrides = {IdleInhibitor: {execSessionAction: argv => { sessionCalls.push(argv); return true; }}};
    const action = {name: 'Shutdown', keyword: 'poweroff', command: ['poweroff'], acceptArgs: true};
    const typed = activation(action, '>poweroff --help', overrides);
    assert.deepEqual(plain(typed.calls), [['exec', 'poweroff', '--help']]);
    const configured = activation({...action, command: ['poweroff', '--help']}, '>poweroff', overrides);
    assert.deepEqual(plain(configured.calls), [['exec', 'poweroff', '--help']]);
    assert.equal(sessionCalls.length, 0);
    assert.equal(args.isSessionShorthand(['loginctl', 'lock-session']), true);
    assert.equal(args.isSessionShorthand(['loginctl', 'terminate-user', '']), true);
    assert.equal(args.isSessionShorthand(['loginctl', 'reboot', '--help']), false);
});
