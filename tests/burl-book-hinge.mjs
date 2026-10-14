import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

for (const [variant, directory, columns, rows, frameWidth, frameHeight] of [
    ['standard', '', 5, 5, 720, 500],
    ['tasks', 'tasks/', 7, 7, 1368, 950],
]) {
    const base = new URL(`../assets/images/book/${directory}`, import.meta.url);
    const {poses, ...page} = JSON.parse(readFileSync(new URL('registration.json', base)));
    test(`${variant}: Blender cover stays bound to its hinge throughout opening`, () => {
        assert.equal(poses.length, page.frames);
        assert.equal(page.frames, columns * rows);
        for (const pose of poses) {
            assert.deepEqual(pose.hingeTop, poses[0].hingeTop);
            assert.deepEqual(pose.hingeBottom, poses[0].hingeBottom);
        }
    });
    test(`${variant}: rendered cover comes toward the viewer and opens past the spine`, () => {
        const middle = poses[Math.round((poses.length - 1) * 0.625)], last = poses.at(-1);
        assert.ok(middle.edgeTop[2] > middle.hingeTop[2] + 5);
        assert.ok(last.edgeTop[0] < last.hingeTop[0]);
        for (const pose of poses)
            for (const point of Object.values(pose))
                assert.ok(point[0] > 0 && point[0] < 1 && point[1] > 0 && point[1] < 1);
    });
    test(`${variant}: live page registration matches the Blender camera`, () => {
        const qml = readFileSync(new URL('../components/widgets/Grimoire.qml', import.meta.url), 'utf8');
        for (const value of [page.left, page.top, page.width, page.height])
            assert.ok(qml.includes(String(Number(value.toFixed(9)))));
    });
    test(`${variant}: opening sheet contains every frame at its intended resolution`, () => {
        const png = readFileSync(new URL('opening-sheet.png', base));
        assert.equal(png.readUInt32BE(16), columns * frameWidth);
        assert.equal(png.readUInt32BE(20), rows * frameHeight);
        assert.ok(columns * frameWidth * rows * frameHeight * 4 < 256 * 1024 * 1024);
    });
}
