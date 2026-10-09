import QtQuick
import QtQuick.Shapes
import qs.components

// DeckledRect — a closed torn-paper outline. One Shape, one ShapePath, one
// PathSvg; the lobe hash and the 90ms / first-build-synchronous rebuild policy
// are LeafEdge's, because retessellating a Shape every frame is the documented
// killer.
//
// A sibling of LeafEdge rather than an extension of it: LeafEdge's contract is a
// BAND (implicitHeight is its depth, one `edge` enum) and three live call sites
// anchor to that, whereas a closed four-sided path has a different implicit-size
// contract entirely.
//
// Deliberately asymmetric. A scroll is torn along its two LONG edges and cut
// straight across top and bottom — which on the world-tree scroll live under the
// coils anyway — so depthV is several times depthH.
//
// `fillItem` takes a texture provider (an Image) so the paper's grain rides
// inside the silhouette with no layer and no MultiEffect. Set `fill` instead for
// a flat tone. Hold `quiet` low across an animation and no rebuild will land on
// a frame where something is moving.
Item {
    id: root

    property real lobeH: 46      // px between lobes, top/bottom
    property real lobeV: 24      // px between lobes, left/right
    property real depthH: 3      // amplitude, top/bottom
    property real depthV: 7      // amplitude, left/right
    property color fill: Woodland.parchmentMid
    property color stroke: "transparent"
    property real strokeW: 1
    property Item texture: null
    property int seed: 0
    property bool quiet: true

    property bool _built: false

    implicitWidth: 240
    implicitHeight: 160

    onWidthChanged: root._schedule()
    onHeightChanged: root._schedule()
    onLobeHChanged: root._schedule()
    onLobeVChanged: root._schedule()
    onDepthHChanged: root._schedule()
    onDepthVChanged: root._schedule()
    onSeedChanged: root._schedule()
    Component.onCompleted: root._schedule()

    function _schedule(): void {
        if (root.width <= 1 || root.height <= 1)
            return;
        // FIRST build synchronous: a fresh sheet must never show a wrong edge,
        // not even for the debounce interval.
        if (root._built)
            rebuildTimer.restart();
        else
            root._rebuild();
    }

    function _rebuild(): void {
        const w = root.width;
        const h = root.height;
        if (w <= 1 || h <= 1)
            return;
        root._built = true;

        const dh = root.depthH;
        const dv = root.depthV;
        const x0 = dv;
        const y0 = dh;
        const x1 = w - dv;
        const y1 = h - dh;
        let k = 0;
        // LeafEdge's deterministic jitter, so the same sheet always tears the
        // same way and nothing reshuffles between frames.
        const j = () => 0.55 + 0.45 * Math.sin((k++ + root.seed) * 12.9898);

        const nT = Math.max(3, Math.round((x1 - x0) / root.lobeH));
        const nV = Math.max(3, Math.round((y1 - y0) / root.lobeV));
        let s = `M ${x0} ${y0}`;
        for (let i = 0; i < nT; i++) {
            const a = x0 + (x1 - x0) * i / nT;
            const b = x0 + (x1 - x0) * (i + 1) / nT;
            s += ` Q ${(a + b) / 2} ${y0 - dh * j()} ${b} ${y0}`;
        }
        for (let i = 0; i < nV; i++) {
            const a = y0 + (y1 - y0) * i / nV;
            const b = y0 + (y1 - y0) * (i + 1) / nV;
            s += ` Q ${x1 + dv * j()} ${(a + b) / 2} ${x1} ${b}`;
        }
        for (let i = nT; i > 0; i--) {
            const a = x0 + (x1 - x0) * i / nT;
            const b = x0 + (x1 - x0) * (i - 1) / nT;
            s += ` Q ${(a + b) / 2} ${y1 + dh * j()} ${b} ${y1}`;
        }
        for (let i = nV; i > 0; i--) {
            const a = y0 + (y1 - y0) * i / nV;
            const b = y0 + (y1 - y0) * (i - 1) / nV;
            s += ` Q ${x0 - dv * j()} ${(a + b) / 2} ${x0} ${b}`;
        }
        svg.path = s + " Z";
    }

    Timer {
        id: rebuildTimer

        interval: 90
        // Not quiet yet: push the rebuild out again rather than tessellate on an
        // animation frame.
        onTriggered: root.quiet ? root._rebuild() : rebuildTimer.restart()
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true
        visible: root._built

        ShapePath {
            fillColor: root.texture ? "transparent" : root.fill
            fillItem: root.texture
            strokeColor: root.stroke
            strokeWidth: root.strokeW

            PathSvg {
                id: svg
            }
        }
    }
}
