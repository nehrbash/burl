import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { test } from "node:test";

const policy = {};
runInNewContext(readFileSync(new URL("../services/MouseSettingsPolicy.js", import.meta.url), "utf8").replace(/^\.pragma library\s*/, ""), policy);
const plain = value => JSON.parse(JSON.stringify(value));

test("mouse profile changes preserve sensitivity and reject arbitrary compositor options", () => {
    assert.equal(policy.command({ accel_profile: "adaptive" }), 'hl.config({ input = { accel_profile = "adaptive" } })');
    assert.throws(() => policy.command({ accel_profile: 'flat"; os.execute("bad")' }));
    assert.throws(() => policy.command({ sensitivity: 2 }));
    assert.throws(() => policy.command({ natural_scroll: "true" }));
    assert.throws(() => policy.command({ kb_layout: "us" }));
    assert.deepEqual(plain(policy.overrides({ accel_profile: "flat", sensitivity: -0.4, natural_scroll: true, left_handed: false, unknown: 1 })),
        { accel_profile: "flat", sensitivity: -0.4, natural_scroll: true, left_handed: false });
});

test("readback accepts native JSON types and custom initial acceleration", () => {
    assert.equal(policy.read("accel_profile", '{"str":"flat"}'), "flat");
    assert.equal(policy.read("accel_profile", '{"str":""}'), "");
    assert.equal(policy.read("sensitivity", '{"float":-0.4}'), -0.4);
    assert.equal(policy.read("natural_scroll", '{"bool":false}'), false);
    assert.throws(() => policy.read("natural_scroll", '{"int":0}'));
    assert.throws(() => policy.read("sensitivity", 'error'));
});

test("confirmation requires every requested setting to match", () => {
    assert.equal(policy.matches({ sensitivity: 0.123456 }, { sensitivity: 0.1234559 }), true);
    assert.equal(policy.matches({ accel_profile: "flat" }, { accel_profile: "adaptive" }), false);
    assert.equal(policy.matches({ left_handed: true }, { left_handed: true, natural_scroll: true }), false);
});
