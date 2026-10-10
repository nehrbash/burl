import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';

const commands = runInNewContext(`${readFileSync(new URL('../services/AppCommands.js', import.meta.url), 'utf8')}\n({resolve, legacyEntry, terminalCommand, fileCommand})`);
const array = value => Array.from(value);
const terminal = {id: 'Alacritty', command: ['/gnu/store/new-alacritty/bin/alacritty'], workingDirectory: ''};

test('desktop identity resolves the current installed executable after an upgrade', () => {
    const before = {...terminal, command: ['/gnu/store/old-alacritty/bin/alacritty']};
    assert.equal(commands.resolve('Alacritty', [], [before], 'foot').command[0], before.command[0]);
    assert.equal(commands.resolve('Alacritty', [], [terminal], 'foot').command[0], terminal.command[0]);
    assert.equal(commands.legacyEntry(before.command, [terminal]).id, 'Alacritty');
});

test('legacy store commands retain custom arguments while resolving a current executable', () => {
    const launch = commands.resolve('', ['/gnu/store/old/bin/alacritty', '--hold', '-e'], [terminal], 'foot');
    assert.deepEqual(array(commands.terminalCommand(launch.command, ['program', 'path with spaces'])),
        [terminal.command[0], '--hold', '-e', 'program', 'path with spaces']);
    assert.equal(commands.legacyEntry(['/gnu/store/old/bin/alacritty', '--hold'], [terminal]), null);
});

test('terminal adapters append execution options once without shell parsing', () => {
    for (const [name, flag] of [['alacritty', '-e'], ['foot', '-e'], ['kitty', '-e'], ['gnome-terminal', '--'], ['xfce4-terminal', '-x']]) {
        assert.deepEqual(array(commands.terminalCommand([name], ['wrapper', 'a; b'])), [name, flag, 'wrapper', 'a; b']);
        assert.deepEqual(array(commands.terminalCommand([name, flag], ['wrapper'])), [name, flag, 'wrapper']);
    }
    assert.throws(() => commands.terminalCommand(['unknown-terminal'], ['program']), /explicit child-command/);
    assert.deepEqual(array(commands.terminalCommand(['custom', '--execute'], ['program'])), ['custom', '--execute', 'program']);
});

test('desktop defaults and explicit commands remain distinct', () => {
    assert.deepEqual(array(commands.resolve('', [], [], 'xdg-open').command), ['xdg-open']);
    assert.deepEqual(array(commands.resolve('', ['custom-player', '--fullscreen'], [], 'xdg-open').command), ['custom-player', '--fullscreen']);
    assert.throws(() => commands.resolve('removed-app', ['old-command'], [], 'xdg-open'), /no longer installed/);
});

test('desktop resolution retains arguments and working directory', () => {
    const entry = {id: 'player', command: ['player', '--audio'], workingDirectory: '/media/test'};
    const resolved = commands.resolve('player', [], [entry], 'xdg-open');
    assert.deepEqual(array(resolved.command), entry.command);
    assert.equal(resolved.workingDirectory, '/media/test');
});

test('ambiguous executable names do not silently migrate user preferences', () => {
    assert.equal(commands.legacyEntry(terminal.command, [terminal, {...terminal, id: 'other'}]), null);
});

test('file launches delegate desktop field-code expansion to GIO', () => {
    const flatpak = {id: 'org.example.Player', command: ['flatpak', 'run', 'org.example.Player', '@@u', '@@']};
    assert.deepEqual(array(commands.fileCommand(flatpak.id, [], [flatpak], '/tmp/a b.mp4')),
        ['gtk-launch', flatpak.id, '/tmp/a b.mp4']);
    assert.deepEqual(array(commands.fileCommand('', [], [], '/tmp/a b.mp4')),
        ['xdg-open', '/tmp/a b.mp4']);
    assert.deepEqual(array(commands.fileCommand('', ['custom', '--play'], [], '/tmp/a b.mp4')),
        ['custom', '--play', '/tmp/a b.mp4']);
    assert.throws(() => commands.fileCommand('removed', [], [], '/tmp/video'), /no longer installed/);
});

test('file launches refresh legacy store executables while preserving custom arguments', () => {
    const player = {id: 'player', command: ['/gnu/store/new-player/bin/player']};
    assert.deepEqual(array(commands.fileCommand('', ['/gnu/store/old-player/bin/player', '--fullscreen'], [player], '/tmp/movie')),
        ['/gnu/store/new-player/bin/player', '--fullscreen', '/tmp/movie']);
});

test('explicit custom executable paths are never replaced by a basename match', () => {
    for (const executable of ['/home/me/bin/alacritty', './bin/alacritty', '../alacritty']) {
        const command = [executable];
        assert.equal(commands.legacyEntry(command, [terminal]), null);
        assert.deepEqual(array(commands.resolve('', command, [terminal], 'foot').command), command);
        assert.deepEqual(array(commands.fileCommand('', command, [terminal], '/tmp/file with spaces')),
            [executable, '/tmp/file with spaces']);
    }
});

test('explicit custom paths may match their exact desktop command', () => {
    const custom = {id: 'custom-terminal', command: ['/home/me/bin/alacritty']};
    assert.equal(commands.legacyEntry(custom.command, [terminal, custom]).id, custom.id);
    assert.deepEqual(array(commands.fileCommand('', custom.command, [terminal, custom], '/tmp/file')),
        ['gtk-launch', custom.id, '/tmp/file']);
    assert.equal(commands.legacyEntry(['alacritty'], [terminal]).id, terminal.id);
});
