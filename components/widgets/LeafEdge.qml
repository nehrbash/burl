import QtQuick
import QtQuick.Shapes
import qs.components

// A scalloped leaf-lobe band for the top or bottom edge of a panel/shelf.
// ONE Shape, ONE ShapePath, ONE PathSvg — never one path per lobe.
// The path string is rebuilt at most once per 90ms and NEVER on a resize
// frame: retessellating a Shape every frame is the documented killer. The
// FIRST build is the exception — it runs the moment a real width arrives, so a
// freshly created band never shows a wrong edge for the debounce interval.
//
//   LeafEdge { anchors.left: parent.left; anchors.right: parent.right
//              anchors.top: parent.top; edge: Qt.TopEdge }
//
// Idle cost: zero — `visible: false` stops painting and the rebuild Timer is
// one-shot, so nothing ticks between geometry changes.
Item {
    id: root

    // Qt.TopEdge: lobes bulge downward from the item's top. Qt.BottomEdge: upward.
    property int edge: Qt.TopEdge
    property real lobe: 26
    property real depth: 7
    property color fill: Woodland.leafFill
    property int seed: 0

    // True once a path has been built from real (non-zero) geometry. Until
    // then `svg.path` is empty and the Shape paints nothing — better than a
    // degenerate one-lobe band.
    property bool _built: false

    // Debounced rebuild, except for the first real geometry, which is built
    // synchronously: at Component.onCompleted the anchors are not yet resolved
    // (width === 0), so waiting for the timer would show wrong art for 90ms.
    function _schedule(): void {
        if (root.width <= 0)
            return;
        if (root._built)
            rebuildTimer.restart();
        else
            root._rebuild();
    }

    function _rebuild(): void {
        if (root.width <= 0)
            return;
        root._built = true;
        const w = Math.max(1, root.width);
        const d = Math.max(1, root.depth);
        const n = Math.max(1, Math.round(w / root.lobe));
        const step = w / n;
        const down = root.edge === Qt.TopEdge;
        const base = down ? 0 : d;
        let s = `M 0 ${base}`;
        for (let i = 0; i < n; i++) {
            // Deterministic per-lobe depth so it reads grown, not tiled.
            const j = 0.75 + 0.25 * Math.sin((i + root.seed) * 12.9898);
            const cy = down ? d * j : d * (1 - j);
            const x0 = i * step;
            s += ` Q ${x0 + step / 2} ${cy} ${x0 + step} ${base}`;
        }
        svg.path = s + " Z";
    }

    implicitHeight: root.depth

    onWidthChanged: root._schedule()
    onDepthChanged: root._schedule()
    onLobeChanged: root._schedule()
    onEdgeChanged: root._schedule()
    Component.onCompleted: root._schedule()

    Timer {
        id: rebuildTimer

        interval: 90
        onTriggered: root._rebuild()
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true

        ShapePath {
            strokeWidth: -1
            fillColor: root.fill

            PathSvg {
                id: svg
            }
        }
    }
}
