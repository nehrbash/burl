import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../modules/dashboard/tree/LivingTree.qml", import.meta.url), "utf8");
const component = source.slice(source.indexOf("component RootNode:"), source.indexOf("component BookStage:"));

function fixture(id = "reboot") {
    let now = 10000;
    const calls = [];
    const node = { action: { id }, requiresHold: id !== "lock", canActivate: true,
        keyboardHeld: false, holdDuration: 1200, holdProgress: 0, heldActionId: "", holdStartedAt: 0 };
    const nodeHover = { pressed: true, containsMouse: true };
    Object.defineProperty(node, "holding", { get: () => node.keyboardHeld || (nodeHover.pressed && nodeHover.containsMouse) });
    const holdDelay = { interval: 1200, running: false,
        start() { this.running = true; }, restart() { this.running = true; }, stop() { this.running = false; } };
    const holdFill = { start() {}, stop() {} };
    const context = { node, nodeHover, holdDelay, holdFill, Date: { now: () => now },
        root: { runSessionAction: action => calls.push(action.id) } };
    for (const name of ["cancelHold", "beginHold", "completeHold", "activateClick", "pressKeyboard"]) {
        const match = component.match(new RegExp(`function ${name}\\(([^)]*)\\): void \\{([\\s\\S]*?)\\n        \\}`));
        assert.ok(match, name);
        node[name] = runInNewContext(`(function(${match[1].replace(/: bool/g, "")}) {${match[2]}\n})`, context);
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


test("keyboard activation preserves the hold and releasing cancels it", () => {
    const f = fixture();
    f.nodeHover.pressed = false;
    f.nodeHover.containsMouse = false;
    f.node.pressKeyboard();
    f.advance(1199);
    f.node.completeHold();
    assert.deepEqual(f.calls, []);
    f.node.cancelHold();
    f.advance(100);
    f.node.completeHold();
    assert.deepEqual(f.calls, []);
    f.node.pressKeyboard();
    f.advance(1200);
    f.node.completeHold();
    assert.deepEqual(f.calls, ["reboot"]);
    assert.equal(f.node.keyboardHeld, false);
});


test("native presses start holds only after MouseArea state settles", { skip: !process.env.QMLTESTRUNNER }, () => {
    const dir = mkdtempSync(join(tmpdir(), "burl-session-hold-"));
    const logic = component.slice(0, component.indexOf("        readonly property var anchor:"))
        .replace("component RootNode: Item", "Item");
    const pointer = component.slice(component.indexOf("        MouseArea {"));
    const qml = `import QtQuick
import QtTest
Item {
    id: root
    width: 300; height: 300
    property var screenState: ({dashboard:true})
    property real roomP: 1
    property real openP: 1
    property string focusedId: ""
    property int hoveredRoot: -1
    property int calls: 0
    function runSessionAction(action) { calls++; }
    ${logic}
        width: 120; height: 120
        readonly property real revealP: 1
        Component.onCompleted: action = ({id:"reboot"})
    ${pointer}
    TestCase {
        name: "SessionHold"; when: windowShown
        function init() { node.cancelHold(); root.calls = 0; mouseMove(node, 60, 60); }
        function test_full_hold() {
            mousePress(node, 60, 60, Qt.LeftButton);
            wait(200);
            compare(node.heldActionId, "reboot");
            compare(root.calls, 0);
            tryCompare(root, "calls", 1, 1600);
            mouseRelease(node, 60, 60, Qt.LeftButton);
            wait(100);
            compare(root.calls, 1);
        }
        function test_short_hold() {
            mousePress(node, 60, 60, Qt.LeftButton);
            wait(200);
            mouseRelease(node, 60, 60, Qt.LeftButton);
            wait(1250);
            compare(root.calls, 0);
        }
        function test_drag_away() {
            mousePress(node, 60, 60, Qt.LeftButton);
            wait(200);
            mouseMove(root, 250, 250);
            wait(1250);
            compare(root.calls, 0);
            mouseRelease(root, 250, 250, Qt.LeftButton);
        }
        function test_keyboard() {
            node.pressKeyboard();
            tryCompare(root, "calls", 1, 1600);
            compare(node.keyboardHeld, false);
        }
    }
}`;
    try {
        writeFileSync(join(dir, "tst_hold.qml"), qml);
        const result = spawnSync(process.env.QMLTESTRUNNER, ["-input", dir], {
            encoding: "utf8", timeout: 15000,
            env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QSG_RHI_BACKEND: "software" },
        });
        assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
});
