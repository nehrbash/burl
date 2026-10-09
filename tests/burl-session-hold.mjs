import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../modules/dashboard/tree/LivingTree.qml", import.meta.url), "utf8");
const component = source.slice(source.indexOf("component RootNode:"), source.indexOf("component BookStage:"));

function fixture(id = "reboot") {
    let now = 10000;
    const calls = [];
    const node = { action: { id }, requiresHold: id !== "lock", canActivate: true,
        holdDuration: 1200, holdProgress: 0, heldActionId: "", holdStartedAt: 0 };
    const nodeHover = { pressed: true, containsMouse: true };
    const holdDelay = { interval: 1200, running: false,
        start() { this.running = true; }, restart() { this.running = true; }, stop() { this.running = false; } };
    const holdFill = { start() {}, stop() {} };
    const context = { node, nodeHover, holdDelay, holdFill, Date: { now: () => now },
        root: { runSessionAction: action => calls.push(action.id) } };
    for (const name of ["cancelHold", "beginHold", "completeHold", "activateClick"]) {
        const match = component.match(new RegExp(`function ${name}\\(\\): void \\{([\\s\\S]*?)\\n        \\}`));
        assert.ok(match, name);
        node[name] = runInNewContext(`(function() {${match[1]}\n})`, context);
    }
    return { node, nodeHover, holdDelay, calls, advance: ms => { now += ms; } };
}

test("session-ending clicks never execute commands; lock remains a click", () => {
    for (const id of ["logout", "reboot", "windows", "hibernate", "shutdown"]) {
        const f = fixture(id);
        f.node.activateClick();
        assert.deepEqual(f.calls, [], id);
    }
    const lock = fixture("lock");
    lock.node.beginHold();
    assert.equal(lock.holdDelay.running, false);
    lock.node.activateClick();
    assert.deepEqual(lock.calls, ["lock"]);
});

test("hold requires the full duration and executes only once", () => {
    const early = fixture();
    early.node.beginHold();
    early.advance(1199);
    early.node.completeHold();
    assert.deepEqual(early.calls, []);
    assert.equal(early.holdDelay.interval, 1);
    early.advance(1);
    early.node.completeHold();
    assert.deepEqual(early.calls, ["reboot"]);
    const complete = fixture();
    complete.node.beginHold();
    complete.advance(1200);
    complete.node.completeHold();
    complete.node.completeHold();
    complete.node.activateClick();
    assert.deepEqual(complete.calls, ["reboot"]);
});

test("release, leaving, hiding, cancellation, and action changes abort a hold", () => {
    const aborts = [
        f => { f.nodeHover.pressed = false; },
        f => { f.nodeHover.containsMouse = false; },
        f => { f.node.canActivate = false; },
        f => { f.node.cancelHold(); },
        f => { f.node.action = { id: "shutdown" }; },
    ];
    for (const abort of aborts) {
        const f = fixture();
        f.node.beginHold();
        f.advance(1300);
        abort(f);
        f.node.completeHold();
        assert.deepEqual(f.calls, []);
        assert.equal(f.holdDelay.running, false);
        assert.equal(f.node.holdProgress, 0);
    }
});

test("reentering after cancellation requires a fresh full hold", () => {
    const f = fixture();
    f.node.beginHold();
    f.advance(1000);
    f.node.cancelHold();
    f.node.beginHold();
    f.advance(300);
    f.node.completeHold();
    assert.deepEqual(f.calls, []);
});

test("pointer handlers cancel and the hold timer has no reduced-motion bypass", () => {
    assert.match(component, /readonly property int holdDuration: 1200/);
    for (const event of ["onReleased", "onCanceled"])
        assert.ok(component.includes(`${event}: node.cancelHold()`));
    assert.match(component, /onExited:\s*\{\s*node\.cancelHold\(\)/);
    assert.match(component, /onCanActivateChanged: if \(!canActivate\) cancelHold\(\)/);
    assert.match(component, /Timer\s*\{\s*id: holdDelay\s*interval: node.holdDuration\s*onTriggered: node.completeHold\(\)/);
});
