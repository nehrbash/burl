import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../services/GameMode.qml", import.meta.url), "utf8");
const PowerProfile = { PowerSaver: 0, Balanced: 1, Performance: 2 };

function harness(profile = PowerProfile.Balanced, manageLlama = true) {
    const commands = [];
    const options = [];
    const reloads = [];
    const props = { effectsApplied: false, llamaStopped: false };
    const stopLlama = { running: false };
    const PowerProfiles = { profile, hasPerformanceProfile: true };
    const root = { ready: true };
    const context = {
        root, props, stopLlama, PowerProfiles, PowerProfile,
        Quickshell: { env: key => key === "BURL_MANAGE_LLAMA" && manageLlama ? "1" : "", execDetached: args => commands.push(Array.from(args)) },
        Hypr: { extras: { applyOptions: opts => options.push(opts), message: msg => reloads.push(msg) } },
        GlobalConfig: { utilities: { toasts: { gameModeChanged: false } } },
    };
    Object.defineProperties(context, {
        ready: { get: () => root.ready },
        enabled: { get: () => PowerProfiles.profile === PowerProfile.Performance },
        available: { get: () => PowerProfiles.hasPerformanceProfile },
    });
    for (const name of ["setProfile", "setEnabled", "toggle", "setDynamicConfs", "restoreLlama", "syncEffects", "llamaStopped"]) {
        const match = source.match(new RegExp(`^    function ${name}\\(([^)]*)\\): \\w+ \\{([\\s\\S]*?)\\n    \\}`, "m"));
        assert.ok(match, `QML function ${name} exists`);
        const args = match[1].replace(/:\s*\w+/g, "");
        root[name] = context[name] = runInNewContext(`(function(${args}) {${match[2]}\n})`, context);
    }
    return { root, props, stopLlama, PowerProfiles, commands, options, reloads };
}

test("quick toggle and profile selector share the system profile", () => {
    const h = harness();
    h.root.toggle();
    assert.equal(h.PowerProfiles.profile, PowerProfile.Performance);
    h.root.syncEffects();
    assert.equal(h.options.length, 1);
    assert.equal(h.stopLlama.running, true);
    h.root.setProfile(PowerProfile.PowerSaver);
    h.root.syncEffects();
    assert.equal(h.PowerProfiles.profile, PowerProfile.PowerSaver);
    assert.deepEqual(h.reloads, ["reload"]);
    h.root.toggle();
    h.root.toggle();
    assert.equal(h.PowerProfiles.profile, PowerProfile.Balanced);
});

test("an external profile change applies the same optimizations once", () => {
    const h = harness();
    h.PowerProfiles.profile = PowerProfile.Performance;
    h.root.syncEffects();
    h.root.syncEffects();
    assert.equal(h.options.length, 1);
    h.PowerProfiles.profile = PowerProfile.Balanced;
    h.root.syncEffects();
    assert.deepEqual(h.reloads, ["reload"]);
});

test("starting in Balanced does not alter visual settings or start local AI", () => {
    const h = harness();
    h.root.syncEffects();
    assert.equal(h.options.length, 0);
    assert.equal(h.reloads.length, 0);
    assert.equal(h.commands.length, 0);
    assert.equal(h.stopLlama.running, false);
});

test("unavailable Performance cannot be selected", () => {
    const h = harness();
    h.PowerProfiles.hasPerformanceProfile = false;
    h.root.toggle();
    assert.equal(h.PowerProfiles.profile, PowerProfile.Balanced);
    h.root.setProfile(PowerProfile.PowerSaver);
    assert.equal(h.PowerProfiles.profile, PowerProfile.PowerSaver);
});

test("local AI that was already stopped is not started on exit", () => {
    const h = harness(PowerProfile.Performance);
    h.root.syncEffects();
    h.root.llamaStopped("Evaluating expression\n#f\n");
    h.root.setEnabled(false);
    h.root.syncEffects();
    assert.equal(h.commands.length, 0);
});

test("local AI stopped by Performance is restored once", () => {
    const h = harness(PowerProfile.Performance);
    h.root.syncEffects();
    h.root.llamaStopped("Evaluating expression\n#t\n");
    h.root.setEnabled(false);
    h.root.syncEffects();
    h.root.restoreLlama();
    assert.deepEqual(h.commands, [["herd", "start", "llama-server"]]);
});

test("leaving Performance before its stop completes restores local AI", () => {
    const h = harness(PowerProfile.Performance);
    h.root.syncEffects();
    h.root.setEnabled(false);
    h.root.syncEffects();
    assert.equal(h.commands.length, 0);
    h.root.llamaStopped("#t\n");
    assert.deepEqual(h.commands, [["herd", "start", "llama-server"]]);
});

test("failed service queries never claim ownership of local AI", () => {
    const h = harness(PowerProfile.Performance);
    h.root.syncEffects();
    h.root.llamaStopped("");
    h.root.setEnabled(false);
    h.root.syncEffects();
    assert.equal(h.commands.length, 0);
});


test("hot reload waits for restored ownership before applying effects", () => {
    const h = harness(PowerProfile.Performance);
    h.root.ready = false;
    h.root.syncEffects();
    assert.equal(h.stopLlama.running, false);
    assert.equal(h.options.length, 0);
    h.props.effectsApplied = true;
    h.props.llamaStopped = true;
    h.root.ready = true;
    h.root.syncEffects();
    assert.equal(h.stopLlama.running, false);
    assert.equal(h.options.length, 0);
    h.root.setEnabled(false);
    h.root.syncEffects();
    assert.deepEqual(h.commands, [["herd", "start", "llama-server"]]);
});

test("performance mode leaves personal services alone without opt-in", () => {
    const h = harness(PowerProfile.Performance, false);
    h.root.syncEffects();
    assert.equal(h.options.length, 1);
    assert.equal(h.stopLlama.running, false);
    h.root.setEnabled(false);
    h.root.syncEffects();
    assert.equal(h.commands.length, 0);
});
