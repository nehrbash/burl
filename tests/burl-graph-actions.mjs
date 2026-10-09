import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const actions = runInNewContext(`${readFileSync(new URL('../modules/launcher/GraphActions.js', import.meta.url), 'utf8')}\n({primary, secondary, execute})`);
function harness(overrides = {}) {
    const commands = [];
    const context = {
        emacsEnabled: true,
        agendaFile: '/home/test/calendar with spaces.org',
        execute: argv => commands.push(Array.from(argv)),
        launch: entry => commands.push(entry),
        dispatch: command => commands.push(command),
        ...overrides
    };
    return { context, commands, visibility: { launcher: true } };
}

test('mail actions retain source identity and sender rather than graph identity', () => {
    const h = harness();
    const source = { id: '<message@example.org>', subject: 'Subject', fromEmail: 'sender@example.org' };
    const secondary = actions.secondary({ kind: 'mail', id: 'mail:' + source.id, source }, h.context);
    const primary = actions.primary('mail', source, h.context);
    assert.deepEqual(Array.from(primary.command), Array.from(secondary[0].command));
    actions.execute(secondary[0], h.context, h.visibility);
    assert.equal(h.commands[0][4], '(mu4e-view-message-with-message-id "<message@example.org>")');
    actions.execute(secondary[1], h.context, h.visibility);
    assert.deepEqual(h.commands[1], ['wl-copy', 'sender@example.org']);
    assert.equal(h.visibility.launcher, false);
});

test('calendar entry actions share the configured source and escaped title', () => {
    const h = harness();
    const source = { id: 'event:1', title: 'A "quoted" meeting' };
    const primary = actions.primary('event', source, h.context);
    const secondary = actions.secondary({ kind: 'event', source }, h.context);
    assert.deepEqual(Array.from(primary.command), Array.from(secondary[1].command));
    assert.ok(primary.command[4].includes(JSON.stringify(h.context.agendaFile)));
    assert.ok(primary.command[4].includes(JSON.stringify(source.title)));
    assert.ok(primary.command[4].includes('(when (search-forward'));
});

test('personal integrations require opt-in without suppressing independent copy actions', () => {
    const h = harness({ emacsEnabled: false });
    const source = { id: 'message', fromEmail: 'sender@example.org' };
    assert.equal(actions.primary('mail', source, h.context), null);
    const secondary = actions.secondary({ kind: 'mail', source }, h.context);
    assert.equal(secondary.length, 1);
    assert.equal(secondary[0].name, 'Copy sender');
    assert.equal(actions.execute(null, h.context, h.visibility), false);
    assert.equal(h.visibility.launcher, true);
    assert.equal(h.commands.length, 0);
});

test('missing source payload cannot issue blank calendar or mail commands', () => {
    const h = harness();
    assert.equal(actions.primary('event', {}, h.context), null);
    assert.equal(actions.primary('event', { title: 'Meeting' }, { ...h.context, agendaFile: '' }), null);
    assert.equal(actions.primary('mail', {}, h.context), null);
    assert.equal(actions.secondary({ kind: 'mail', id: 'mail:unusable' }, h.context).length, 0);
    assert.equal(actions.execute({}, h.context, h.visibility), false);
    assert.equal(h.visibility.launcher, true);
});

test('executor failures preserve the launcher and propagate to the caller', () => {
    const h = harness({ execute: () => { throw new Error('unavailable'); } });
    assert.throws(() => actions.execute({ command: ['emacsclient'] }, h.context, h.visibility), /unavailable/);
    assert.equal(h.visibility.launcher, true);
});

test('application and compositor actions use injected adapters', () => {
    const h = harness();
    const entry = { id: 'app.desktop' };
    actions.execute(actions.secondary({ kind: 'app', entry, label: 'App' }, h.context)[0], h.context, h.visibility);
    assert.equal(h.commands[0], entry);
    actions.execute(actions.secondary({ kind: 'client', clientAddress: '0x123', label: 'Window' }, h.context)[0], h.context, h.visibility);
    assert.equal(h.commands[1], 'hl.dsp.window.kill({ window = "address:0x123" })');
});

test('graph nodes retain each integration payload and delegate primary activation', () => {
    const graph = readFileSync(new URL('../modules/launcher/GraphView.qml', import.meta.url), 'utf8');
    for (const [kind, variable] of [['recent', 'r'], ['bookmark', 'bm'], ['roam', 'n'], ['project', 'p'], ['mail', 'msg'], ['event', 'ev']]) {
        assert.ok(graph.includes(`kind: "${kind}",\n                source: ${variable},`));
        assert.ok(graph.includes(`onClicked: vis => root.activateSource("${kind}", ${variable}, vis)`));
    }
});

test('same-shape refresh updates action payload and primary callback without replacing nodes', () => {
    const graph = readFileSync(new URL('../modules/launcher/GraphView.qml', import.meta.url), 'utf8');
    const begin = graph.indexOf('        const sameShape =');
    const end = graph.indexOf('        const positions = {};', begin);
    assert.ok(begin >= 0 && end > begin);
    const h = harness();
    const oldSource = { id: 'mail-id', fromEmail: 'old@example.org' };
    const newSource = { id: 'mail-id', fromEmail: 'new@example.org' };
    const node = { id: 'mail:mail-id', kind: 'mail', label: 'Old', source: oldSource };
    const refreshed = { ...node, label: 'New', source: newSource,
        onClicked: visibility => actions.execute(actions.primary('mail', newSource, h.context), h.context, visibility) };
    const context = { nodes: [node], out: [refreshed], browsing: false, rescore() {} };
    runInNewContext(`(function() {${graph.slice(begin, end)}})()`, context);
    assert.equal(context.nodes[0], node);
    assert.equal(node.source, newSource);
    assert.equal(node.onClicked, refreshed.onClicked);
    actions.execute(actions.secondary(node, h.context)[1], h.context, h.visibility);
    assert.deepEqual(h.commands[0], ['wl-copy', 'new@example.org']);
    node.onClicked(h.visibility);
    assert.equal(h.commands[1][4], '(mu4e-view-message-with-message-id "mail-id")');
});
