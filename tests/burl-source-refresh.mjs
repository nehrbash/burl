import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../modules/launcher/Wrapper.qml', import.meta.url), 'utf8');
const body = source.match(/function reloadWhenReady\(\): void \{([\s\S]*?)\n    \}/)[1];

test('deferred opening refresh recovers calendar and Emacs sources once ready', () => {
    const calls = [];
    const state = {refreshPending: true, readyForReload: false,
        CalendarSources: {reload: () => calls.push('calendar')},
        EmacsSources: {reload: () => calls.push('emacs')},
        SpotifySources: {authed: true, reload: () => calls.push('spotify')}};
    vm.createContext(state);
    const run = () => vm.runInContext(`(function () { ${body} })()`, state);
    run();
    assert.deepEqual(calls, []);
    assert.equal(state.refreshPending, true);
    state.readyForReload = true;
    run();
    run();
    assert.deepEqual(calls, ['calendar', 'emacs']);
    assert.equal(state.refreshPending, false);
});
