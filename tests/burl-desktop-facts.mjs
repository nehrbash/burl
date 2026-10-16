import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../utils/DesktopFacts.js", import.meta.url), "utf8");
const facts = runInNewContext(`${source.replace(/^\.pragma library\s*/, "")}\n({normalFullscreenFor, visibleFullscreenFor, anyNormalFullscreen})`);
const workspace = (name, fullscreen) => ({ name, toplevels: { values: [{ lastIpcObject: { fullscreen } }] } });
const monitor = (activeWorkspace, specialName = "") => ({ activeWorkspace, lastIpcObject: { specialWorkspace: { name: specialName } } });

test("normal fullscreen distinguishes maximized windows", () => {
    assert.equal(facts.normalFullscreenFor(monitor(workspace("1", 1))), false);
    assert.equal(facts.normalFullscreenFor(monitor(workspace("1", 2))), true);
});

test("visible special workspace masks normal fullscreen without erasing its fact", () => {
    const normal = workspace("1", 2);
    const special = workspace("special:notes", 0);
    const screen = monitor(normal, special.name);
    assert.equal(facts.normalFullscreenFor(screen), true);
    assert.equal(facts.visibleFullscreenFor(screen, [normal, special]), false);
    special.toplevels.values[0].lastIpcObject.fullscreen = 2;
    assert.equal(facts.visibleFullscreenFor(screen, [normal, special]), true);
    screen.lastIpcObject.specialWorkspace.name = "";
    assert.equal(facts.visibleFullscreenFor(screen, [normal, special]), true);
});

test("special fullscreen is visible without claiming normal fullscreen", () => {
    const normal = workspace("1", 0);
    const special = workspace("special:media", 2);
    const screen = monitor(normal, special.name);
    assert.equal(facts.normalFullscreenFor(screen), false);
    assert.equal(facts.visibleFullscreenFor(screen, [normal, special]), true);
    assert.equal(facts.anyNormalFullscreen([screen]), false);
});

test("unknown special workspace remains non-fullscreen until metadata arrives", () => {
    const screen = monitor(workspace("1", 2), "special:pending");
    assert.equal(facts.visibleFullscreenFor(screen, []), false);
    assert.equal(facts.visibleFullscreenFor(screen, [workspace("special:pending", 2)]), true);
});

test("all-monitor admission and focused-visible expiry preserve distinct scopes", () => {
    const focused = monitor(workspace("1", 0));
    const other = monitor(workspace("2", 2));
    assert.equal(facts.anyNormalFullscreen([focused, other]), true);
    assert.equal(facts.visibleFullscreenFor(focused, []), false);
    assert.equal(facts.anyNormalFullscreen([focused]), false);
});

test("missing monitors and incomplete metadata have no fullscreen fact", () => {
    for (const screen of [null, undefined, {}, monitor(null)]) {
        assert.equal(facts.normalFullscreenFor(screen), false);
        assert.equal(facts.visibleFullscreenFor(screen, []), false);
    }
    assert.equal(facts.anyNormalFullscreen([]), false);
    assert.equal(facts.anyNormalFullscreen(undefined), false);
});
