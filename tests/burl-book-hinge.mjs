import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
const {poses, ...page} = JSON.parse(readFileSync(new URL('../assets/images/book/registration.json', import.meta.url)));
test('Blender cover stays bound to its hinge throughout opening', () => {
    assert.equal(poses.length, 25);
    for (const pose of poses) {
        assert.deepEqual(pose.hingeTop, poses[0].hingeTop);
        assert.deepEqual(pose.hingeBottom, poses[0].hingeBottom);
    }
});
test('rendered cover comes toward the viewer and opens past the spine', () => {
    const middle = poses[15], last = poses.at(-1);
    assert.ok(middle.edgeTop[2] > middle.hingeTop[2] + 5);
    assert.ok(last.edgeTop[0] < last.hingeTop[0]);
    for (const pose of poses)
        for (const point of Object.values(pose))
            assert.ok(point[0] > 0 && point[0] < 1 && point[1] > 0 && point[1] < 1);
});
test('live page registration matches the Blender camera', () => {
    const qml = readFileSync(new URL('../components/widgets/Grimoire.qml', import.meta.url), 'utf8');
    for (const value of [page.left, page.top, page.width, page.height])
        assert.ok(qml.includes(String(Number(value.toFixed(9)))));
});
