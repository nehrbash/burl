import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

function qmlFunction(file, name, context) {
    const source = readFileSync(new URL(`../services/${file}`, import.meta.url), "utf8");
    const match = source.match(new RegExp(`^([ \t]*)function ${name}\\(([^)]*)\\): \\w+ \\{([\\s\\S]*?)\\n\\1\\}`, "m"));
    assert.ok(match, `${name} exists in ${file}`);
    const args = match[2].replace(/:\s*\w+/g, "");
    return runInNewContext(`(function(${args}) {${match[3]}\n})`, context);
}

function netDev(...interfaces) {
    return ["Inter-| Receive | Transmit", " face | bytes packets errs drop fifo frame compressed multicast | bytes",
        ...interfaces.map(([name, rx, tx]) => `${name}:${rx} 0 0 0 0 0 0 0 ${tx} 0 0 0 0 0 0 0`)].join("\n");
}

function network() {
    let now = 0;
    const root = { sampling: true, _previousCounters: null, _prevTimestamp: 0,
        _downloadSpeed: 0, _uploadSpeed: 0, _downloadTotal: 0, _uploadTotal: 0 };
    const context = { root, Date: { now: () => now }, downloadHistory: [], uploadHistory: [] };
    root.parseNetDev = qmlFunction("NetworkUsage.qml", "parseNetDev", context);
    root.resetSampling = qmlFunction("NetworkUsage.qml", "resetSampling", context);
    const sample = qmlFunction("NetworkUsage.qml", "sample", context);
    return { root, context, sample(time, ...interfaces) { now = time; sample(netDev(...interfaces)); } };
}

test("existing interfaces contribute observed traffic at the elapsed sample rate", () => {
    const n = network();
    n.sample(0, ["eth0", 100000000, 200000000]);
    n.sample(2000, ["eth0", 100000500, 200000100]);
    assert.equal(n.root._downloadSpeed, 250);
    assert.equal(n.root._uploadSpeed, 50);
    assert.equal(n.root._downloadTotal, 500);
    assert.equal(n.root._uploadTotal, 100);
    assert.equal(n.context.downloadHistory.length, 1);
});

test("a newly observed interface's historical counters do not enter totals", () => {
    const n = network();
    n.sample(0, ["eth0", 100, 100]);
    n.sample(1000, ["eth0", 120, 110], ["tun0", 1e12, 1e12]);
    assert.equal(n.root._downloadTotal, 20);
    assert.equal(n.root._uploadTotal, 10);
    n.sample(2000, ["eth0", 130, 120], ["tun0", 1e12 + 30, 1e12 + 40]);
    assert.equal(n.root._downloadSpeed, 40);
    assert.equal(n.root._uploadSpeed, 50);
});

test("removed interfaces do not cause wraparound spikes or erase totals", () => {
    const n = network();
    n.sample(0, ["eth0", 100, 100], ["veth0", 1e12, 1e12]);
    n.sample(1000, ["eth0", 120, 110]);
    assert.equal(n.root._downloadSpeed, 20);
    assert.equal(n.root._uploadTotal, 10);
    n.sample(2000);
    assert.equal(n.root._downloadSpeed, 0);
    assert.equal(n.root._downloadTotal, 20);
    n.sample(3000, ["eth0", 1e12, 1e12]);
    assert.equal(n.root._downloadSpeed, 0);
    assert.equal(n.root._downloadTotal, 20);
});

test("counter resets establish a baseline independently in each direction", () => {
    const n = network();
    n.sample(0, ["eth0", 1000, 1000]);
    n.sample(1000, ["eth0", 10, 1010]);
    assert.equal(n.root._downloadTotal, 0);
    assert.equal(n.root._uploadTotal, 10);
    n.sample(2000, ["eth0", 30, 5]);
    assert.equal(n.root._downloadTotal, 20);
    assert.equal(n.root._uploadTotal, 10);
    assert.equal(n.root._uploadSpeed, 0);
});

test("loopback and malformed counters do not contribute traffic", () => {
    const n = network();
    n.sample(0, ["lo", 100, 100], ["eth0", 10, 10]);
    n.sample(1000, ["lo", 1e12, 1e12], ["eth0", 20, 30], ["bad", "NaN", 40]);
    assert.equal(n.root._downloadTotal, 10);
    assert.equal(n.root._uploadTotal, 20);
    assert.equal(n.root._previousCounters.bad, undefined);
});

test("a nonpositive time interval preserves the last valid baseline", () => {
    const n = network();
    n.sample(1000, ["eth0", 100, 100]);
    n.sample(1000, ["eth0", 110, 110]);
    n.sample(2000, ["eth0", 120, 130]);
    assert.equal(n.root._downloadSpeed, 20);
    assert.equal(n.root._uploadSpeed, 30);
});

test("sampling resumes with a fresh baseline and ignores late inactive reads", () => {
    const n = network();
    n.sample(0, ["eth0", 100, 100]);
    n.sample(1000, ["eth0", 120, 130]);
    n.root.sampling = false;
    n.root.resetSampling();
    n.sample(2000, ["eth0", 1000, 1000]);
    assert.equal(n.root._previousCounters, null);
    assert.equal(n.root._downloadTotal, 20);
    assert.equal(n.root._downloadSpeed, 0);
    assert.equal(n.root._uploadSpeed, 0);
    n.root.sampling = true;
    n.root.resetSampling();
    n.sample(30000, ["eth0", 1e12, 1e12]);
    assert.equal(n.root._downloadTotal, 20);
    assert.equal(n.root._downloadSpeed, 0);
    n.sample(31000, ["eth0", 1e12 + 50, 1e12 + 60]);
    assert.equal(n.root._downloadTotal, 70);
    assert.equal(n.root._uploadTotal, 90);
    assert.equal(n.root._downloadSpeed, 50);
});

test("recording duration advances only during capture", () => {
    const props = { elapsed: 0 };
    const root = { state: "idle" };
    const tick = qmlFunction("Recorder.qml", "onSecondsChanged", { props, root });
    for (const state of ["idle", "selecting", "starting", "paused", "saving"]) {
        root.state = state;
        tick();
    }
    assert.equal(props.elapsed, 0);
    root.state = "recording";
    tick();
    assert.equal(props.elapsed, 1);
});
