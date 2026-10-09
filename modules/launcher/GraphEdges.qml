pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.services

Item {
    id: root

    required property var graph
    property real progress: 1
    property var paths: ["", "", "", ""]
    readonly property bool filtering: (graph.query ?? "").trim() !== "" || graph.scopeSegments.length > 0
    readonly property color edgeColor: Woodland.mix(Colours.palette.m3outline, Woodland.parchmentEdge, 0.30)

    function refresh(): void {
        Qt.callLater(rebuildPaths);
    }

    function rebuildPaths(): void {
        const positions = graph.snap;
        const pairs = graph.edgePairs;
        const bands = [[], [], [], []];
        const focus = graph.highlightFocus;
        const centreX = graph.width / 2;
        const centreY = graph.height / 2;
        const t = Math.max(0, Math.min(1, progress));
        const u = 1 - t;
        for (const edge of pairs) {
            const i = edge.x, j = edge.y;
            const x = positions[i * 3], y = positions[i * 3 + 1];
            const endX = positions[j * 3], endY = positions[j * 3 + 1];
            if (x === undefined || endX === undefined)
                continue;
            let band = 0;
            if (focus >= 0)
                band = i === focus || j === focus ? 1 : 0;
            else if (filtering) {
                const depth = Math.min(graph.depthToMatch?.[i] ?? Infinity, graph.depthToMatch?.[j] ?? Infinity);
                band = depth <= 0 ? 0 : depth <= graph.elevationDepth ? 1 : 2;
            }
            const midX = (x + endX) / 2, midY = (y + endY) / 2;
            const dx = endX - x, dy = endY - y;
            const bow = dx * (midY - centreY) - dy * (midX - centreX) >= 0 ? 0.07 : -0.07;
            const controlX = midX - dy * bow, controlY = midY + dx * bow;
            bands[band].push(`M ${x} ${y} Q ${x + (controlX - x) * t} ${y + (controlY - y) * t} ${u*u*x + 2*u*t*controlX + t*t*endX} ${u*u*y + 2*u*t*controlY + t*t*endY}`);
        }
        const current = graph.currentNode;
        if (current >= 0 && positions[current * 3] !== undefined) {
            const adjacent = new Set(graph.nodeAdjacency[current] ?? []);
            for (const neighbor of graph.navSlots) {
                if (neighbor >= 0 && adjacent.has(neighbor) && positions[neighbor * 3] !== undefined)
                    bands[3].push(`M ${positions[current * 3]} ${positions[current * 3 + 1]} L ${positions[neighbor * 3]} ${positions[neighbor * 3 + 1]}`);
            }
        }
        paths = bands.map(band => band.join(" "));
    }

    Item {
        opacity: root.progress

        Repeater {
            model: 4

            delegate: Shape {
                id: band
                required property int index
                // Canvas rasterizes intersecting paths on the GUI thread in Qt 6.
                preferredRendererType: Shape.CurveRenderer
                asynchronous: true

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: band.index === 3 ? Qt.alpha(Colours.palette.m3primary, 0.9)
                        : Qt.alpha(root.edgeColor, root.graph.highlightFocus >= 0
                            ? (band.index === 1 ? 0.65 : 0.07)
                            : root.filtering ? [0.75, 0.30, 0.065][band.index] : 0.15)
                    strokeWidth: band.index === 3 ? 1.6 : root.graph.highlightFocus >= 0
                        ? (band.index === 1 ? 1.5 : 0.8)
                        : root.filtering ? [1.6, 1.2, 0.8][band.index] : 1
                    PathSvg { path: root.paths[band.index] }
                }
            }
        }
    }
}
