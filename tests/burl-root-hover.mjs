import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("../modules/launcher/Content.qml", import.meta.url), "utf8");
const tree = readFileSync(new URL("../modules/dashboard/tree/LivingTree.qml", import.meta.url), "utf8");
const paths = {};
runInNewContext(readFileSync(new URL("../components/widgets/PaintedTreePaths.js", import.meta.url), "utf8").replace(".pragma library", ""), paths);
const endpoints = paths.roots.map(route => route.points.at(-1));

function area(id) {
    const at = source.indexOf(`id: ${id}`);
    const start = source.lastIndexOf("MouseArea {", at);
    let depth = 0;
    for (let i = source.indexOf("{", start); i < source.length; i++) {
        if (source[i] === "{") depth++;
        if (source[i] === "}" && --depth === 0) return source.slice(start, i + 1);
    }
    throw new Error(`missing MouseArea ${id}`);
}

function closeRect(width, height) {
    const context = { root: { width, height } };
    const compact = runInNewContext(area("closeTree").match(/property bool compact: (.*)/)[1], context);
    const scope = { ...context, compact, width: 44, height: 44, parent: { width, height }, Tokens: { spacing: { large: 24 } } };
    return ["x", "y"].map(key => runInNewContext(area("closeTree").match(new RegExp(`^            ${key}: (.*)`, "m"))[1], scope));
}

function rootRects(width, height) {
    const artHeight = height * 0.97;
    const artWidth = Math.min(width * 0.88, artHeight * 1.12);
    const radius = (0.026 * artWidth + 8) * 1.18;
    return endpoints.map(([x, y]) => ({ x: (width - artWidth) / 2 + x * artWidth, y: height - artHeight + y * artHeight, radius }));
}

const sizes = [[1920, 1080], [1280, 720], [800, 600], [800, 500], [799, 500], [640, 360], [360, 640]];

test("Close hover is separate from the root-row floor dismissal", () => {
    assert.match(area("groundBand"), /hoverEnabled: false/);
    assert.match(area("groundBand"), /onClicked: root.dismiss\(\)/);
    assert.match(area("closeTree"), /onClicked: root.dismiss\(\)/);
    assert.doesNotMatch(source, /groundBand\.containsMouse/);
    assert.match(tree, /anchors\.margins: -8/);
    assert.match(tree, /hoverBump: nodeHover\.containsMouse \? 1\.18 : 1/);
});

test("Close hit target does not overlap enlarged root targets on desktop or compact surfaces", () => {
    for (const [width, height] of sizes) {
        const [x, y] = closeRect(width, height);
        for (const node of rootRects(width, height)) {
            const overlap = x < node.x + node.radius && x + 44 > node.x - node.radius
                && y < node.y + node.radius && y + 44 > node.y - node.radius;
            assert.equal(overlap, false, `${width}x${height}: Close overlaps root at ${node.x},${node.y}`);
        }
    }
});

test("native pointer crossings distinguish root gaps from the Close target", { skip: !process.env.QMLTESTRUNNER }, () => {
    const dir = mkdtempSync(join(tmpdir(), "burl-root-hover-"));
    const close = area("closeTree").replaceAll("Tokens.spacing.large", "24")
        .replaceAll("Woodland.barkEdge", '"#201a16"').replaceAll("Woodland.parchment", '"#eee0ce"')
        .replace("MaterialIcon {", "Text {").replace("fontStyle: Tokens.font.icon.small", "font.pixelSize: 20")
        .replace(/Anim \{\s*type: Anim.FastEffects\s*\}/, "NumberAnimation { duration: 100 }");
    const qml = `import QtQuick
import QtTest
Item {
    id: root
    width: 1920; height: 1080
    property bool atTree: true
    property int dismissals: 0
    function dismiss() { dismissals++; }
    ${area("groundBand")}
    Repeater {
        id: nodes
        model: ${JSON.stringify(endpoints)}
        delegate: MouseArea {
            required property var modelData
            readonly property real artHeight: root.height * 0.97
            readonly property real artWidth: Math.min(root.width * 0.88, artHeight * 1.12)
            readonly property real radius: (0.026 * artWidth + 8) * 1.18
            x: (root.width - artWidth) / 2 + modelData[0] * artWidth - radius
            y: root.height - artHeight + modelData[1] * artHeight - radius
            width: radius * 2; height: radius * 2
            z: 3
            hoverEnabled: true
        }
    }
    Item { anchors.fill: parent; z: 4; ${close} }
    TestCase {
        name: "RootHover"
        when: windowShown
        function test_crossings_data() {
            return ${JSON.stringify(sizes.map(([width, height]) => ({ tag: `${width}x${height}`, width, height })))};
        }
        function test_crossings(data) {
            root.width = data.width; root.height = data.height;
            wait(20);
            const first = nodes.itemAt(0), second = nodes.itemAt(1);
            const gapX = first.x + first.width < second.x
                ? (first.x + first.width + second.x) / 2 : Math.max(1, first.x - 8);
            const gapY = Math.max(first.y + first.height / 2, second.y + second.height / 2);
            groundBand.hoverEnabled = true;
            mouseMove(root, gapX, gapY);
            verify(groundBand.containsMouse, "old floor hover lights Close between roots");
            groundBand.hoverEnabled = false;
            for (let i = 0; i < 3; ++i) {
                mouseMove(first, first.width / 2, first.height / 2);
                verify(first.containsMouse);
                verify(!closeTree.containsMouse);
                mouseMove(root, gapX, gapY);
                verify(!closeTree.containsMouse);
                mouseMove(second, second.width / 2, second.height / 2);
                verify(second.containsMouse);
                verify(!closeTree.containsMouse);
            }
            mouseMove(closeTree, 22, 22);
            verify(closeTree.containsMouse);
            const before = root.dismissals;
            mouseClick(closeTree, 22, 22);
            compare(root.dismissals, before + 1);
            mouseClick(root, gapX, gapY);
            compare(root.dismissals, before + 2);
        }
    }
}`;
    try {
        writeFileSync(join(dir, "tst_roots.qml"), qml);
        const result = spawnSync(process.env.QMLTESTRUNNER, ["-input", dir], { encoding: "utf8", timeout: 20000,
            env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QSG_RHI_BACKEND: "software" } });
        assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
});
