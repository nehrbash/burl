import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const policy = {};
runInNewContext(readFileSync(new URL("../services/CompositorEffectPolicy.js", import.meta.url), "utf8").replace(/^\.pragma library\s*/, ""), policy);
const plain = value => JSON.parse(JSON.stringify(value));

function harness() {
    let state = policy.initialState();
    let baseline = { "general:gaps_in": 7, "decoration:blur:enabled": 1, "general:border_size": 3 };
    let actual = { ...baseline };
    let reloads = 0;
    const batches = [];
    function accept(change) {
        state = change.state;
        if (change.reload) reloads++;
        if (change.options !== null) {
            Object.assign(actual, change.options);
            batches.push(plain(change.options));
        }
    }
    return {
        request: (mode, enabled) => accept(policy.request(state, mode, enabled)),
        event: () => { actual = { ...baseline }; accept(policy.reloaded(state)); },
        finish: success => accept(policy.finished(state, success)),
        baseline: value => { baseline = value; },
        get state() { return state; },
        get actual() { return actual; },
        get reloads() { return reloads; },
        batches
    };
}

test("both mode orders produce the same union and focus exit preserves performance", () => {
    for (const order of [["focus", "performance"], ["performance", "focus"]]) {
        const h = harness();
        order.forEach(mode => h.request(mode, true));
        assert.equal(h.actual["decoration:blur:enabled"], 0);
        assert.equal(h.actual["general:gaps_in"], 0);
        assert.equal(Object.keys(h.state.applied).length, 10);
        h.request("focus", false);
        assert.equal(h.reloads, 0);
        assert.equal(Object.keys(h.state.applied).length, 10);
        h.request("performance", false);
        assert.equal(h.reloads, 1);
        h.event(); h.finish(true);
        assert.deepEqual(h.actual, { "general:gaps_in": 7, "decoration:blur:enabled": 1, "general:border_size": 3 });
    }
});

test("leaving performance restores its exclusive options and reapplies focus", () => {
    const h = harness();
    h.request("focus", true); h.request("performance", true);
    h.request("performance", false);
    assert.equal(h.reloads, 1);
    h.event();
    const count = h.batches.length;
    h.finish(true);
    assert.equal(h.batches.length, count);
    assert.equal(h.actual["decoration:blur:enabled"], 1);
    assert.equal(h.actual["general:border_size"], 3);
    assert.equal(h.actual["general:gaps_in"], 0);
});

test("reload uses latest requests even when toggles arrive before or after its event", () => {
    for (const eventFirst of [false, true]) {
        const h = harness();
        h.request("performance", true); h.request("performance", false);
        if (eventFirst) h.event();
        h.request("focus", true); h.request("performance", true); h.request("focus", false);
        if (!eventFirst) h.event();
        h.finish(true);
        assert.equal(h.reloads, 1);
        assert.equal(h.actual["decoration:blur:enabled"], 0);
        assert.equal(h.actual["general:gaps_in"], 0);
        assert.equal(h.state.pending, false);
    }
});

test("external reload uses new config baseline in every mode combination", () => {
    for (const focus of [false, true]) for (const performance of [false, true]) {
        const h = harness();
        h.request("focus", focus); h.request("performance", performance);
        h.baseline({ "general:gaps_in": 19, "decoration:blur:enabled": 1, "general:border_size": 8 });
        h.event();
        assert.equal(h.actual["general:gaps_in"], focus || performance ? 0 : 19);
        assert.equal(h.actual["general:border_size"], performance ? 1 : 8);
        assert.equal(h.reloads, 0);
    }
});

test("failed or timed-out reload releases pending and retries restoration", () => {
    const h = harness();
    h.request("performance", true); h.request("performance", false);
    h.finish(false);
    assert.equal(h.state.pending, false);
    h.request("performance", false);
    assert.equal(h.reloads, 2);
    h.event(); h.finish(true);
    assert.equal(h.actual["decoration:blur:enabled"], 1);
});

test("successful command completion reapplies requests if the event was missed", () => {
    const h = harness();
    h.request("performance", true); h.request("performance", false);
    h.request("focus", true);
    h.finish(true);
    assert.equal(h.state.pending, false);
    assert.equal(h.batches.at(-1)["general:gaps_in"], 0);
    assert.equal(Object.keys(h.batches.at(-1)).length, 6);
});

test("Lua commands follow the native adapter's nested config syntax", () => {
    assert.deepEqual(plain(policy.commands({ "decoration:blur:enabled": 0, "general:gaps_in": 0 })), [
        "eval hl.config({ decoration = { blur = { enabled = 0 } } })",
        "eval hl.config({ general = { gaps_in = 0 } })"
    ]);
});
