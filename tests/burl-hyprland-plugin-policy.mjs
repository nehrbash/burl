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
    assert.equal(text, "return {\n\n}\n");
});
