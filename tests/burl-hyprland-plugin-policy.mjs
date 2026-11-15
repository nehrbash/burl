import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { test } from "node:test";

const policy = {};
runInNewContext(readFileSync(new URL("../services/HyprlandPluginPolicy.js", import.meta.url), "utf8").replace(/^\.pragma library\s*/, ""), policy);
const plain = value => JSON.parse(JSON.stringify(value));
const installed = [{ id: "hyprspace", path: "/plugins/Hyprspace.so" }, { id: "hyprbars", path: "/plugins/hyprbars.so" }];

test("manifest discovers installed paths without evaluating Lua", () => {
    assert.deepEqual(plain(policy.manifest('return { "/plugins/Hyprspace.so", "relative.so", "/plugins/hyprbars.so" }')), installed);
});

test("unconfigured plugins preserve their actual state", () => {
    const entries = policy.entries(installed, [{ name: "Hyprspace" }], {}, true);
    assert.equal(entries[0].enabled, true);
    assert.equal(entries[0].desired, true);
    assert.equal(entries[1].enabled, false);
    assert.equal(entries[1].desired, false);
});

test("performance pauses only opted-in enabled plugins", () => {
    const choices = { hyprspace: { enabled: true, disableInPerformance: true }, hyprbars: { enabled: false, disableInPerformance: true } };
    assert.equal(policy.entries(installed, [], choices, true)[0].desired, false);
    assert.equal(policy.entries(installed, [], choices, false)[0].desired, true);
    assert.equal(policy.entries(installed, [], choices, false)[1].desired, false);
    assert.match(policy.loaderSettings(choices, true), /\["hyprspace"\] = false/);
    assert.match(policy.loaderSettings(choices, false), /\["hyprspace"\] = true/);
});

test("startup settings ignore unsafe or malformed preference keys", () => {
    const text = policy.loaderSettings({ 'bad"key': { enabled: true }, incomplete: {} }, false);
    assert.equal(text, 'return {\n  ["hyprmist"] = true,\n}\n');
});

test("Power Saver suppresses mist without changing saved choices or other plugins", () => {
    const plugins = [{ id: "hyprmist", path: "/plugins/hyprmist.so" }, ...installed];
    const choices = { hyprmist: { enabled: true }, hyprbars: { enabled: true } };
    const saved = JSON.stringify(choices);
    const entries = policy.entries(plugins, [{ name: "hyprmist" }, { name: "hyprbars" }], choices, false, true);
    assert.equal(entries[0].enabled, true);
    assert.equal(entries[0].desired, false);
    assert.equal(entries[0].pausedForPowerSaver, true);
    assert.equal(entries[2].desired, true);
    assert.equal(policy.entries(plugins, [], choices, false, false)[0].desired, true);
    assert.match(policy.loaderSettings(choices, false, true), /\["hyprmist"\] = false/);
    assert.match(policy.loaderSettings(choices, false, false), /\["hyprmist"\] = true/);
    assert.equal(JSON.stringify(choices), saved);
    const disabled = { hyprmist: { enabled: false } };
    assert.equal(policy.entries(plugins, [], disabled, false, true)[0].desired, false);
    assert.equal(policy.entries(plugins, [], disabled, false, false)[0].desired, false);
});

test("Power Saver prevents unconfigured mist from reloading", () => {
    assert.match(policy.loaderSettings({}, false, true), /\["hyprmist"\] = false/);
    const entry = policy.entries([{ id: "hyprmist" }], [{ name: "hyprmist" }], {}, false, true)[0];
    assert.equal(entry.desired, false);
    assert.equal(entry.enabled, true);
    assert.equal(policy.entries([{ id: "hyprmist" }], [], {}, false, false)[0].desired, true);
    assert.match(policy.loaderSettings({}, false, false), /\["hyprmist"\] = true/);
});
