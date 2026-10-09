pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components

// A vine that creeps along one edge as `progress` goes 0 -> 1. The path is
// STATIC and built once; the reveal is a CLIP, never a re-path — animating
// path control points retessellates the whole curve every frame.
//
//   GrowIn { id: grow }
//   VineGrow { anchors.left: ...; progress: grow.progress; length: parent.height }
//
// Idle cost: zero — one static Shape (1 ShapePath) plus 3-4 Rectangles; no
// timer, no animator of its own. All motion comes from the caller's GrowIn.
Item {
    id: root

    // Qt.LeftEdge / Qt.RightEdge climb vertically; Qt.TopEdge / Qt.BottomEdge run horizontally.
    property int edge: Qt.LeftEdge
    readonly property bool horizontal: root.edge === Qt.TopEdge || root.edge === Qt.BottomEdge
    property real progress: 1
    property real thickness: 2
    property real bow: 9
    property color stroke: Woodland.vineStroke
    property color leaf: Woodland.leafFillDeep
    property real leafSize: 9
    // Fractions along the vine where leaves sit. Keep it to 3-4: each is one Shape-free Rectangle-pair.
    property var leafStops: [0.22, 0.51, 0.79]

    implicitWidth: root.horizontal ? 0 : root.bow * 2 + root.thickness
    implicitHeight: root.horizontal ? root.bow * 2 + root.thickness : 0

    Item {
        id: clipper

        // Reveal by clipping the finished vine — one animated width/height.
        // Clip must open from the path's start (left horizontal, bottom
        // vertical — PathSvg starts at `M bow height`), so a vertical clipper
        // is bottom-anchored; `content` slides with it to stay registered.
        clip: true
        y: root.horizontal ? 0 : root.height - height
        width: root.horizontal ? root.width * root.progress : root.width
        height: root.horizontal ? root.height : root.height * root.progress

        Item {
            id: content

            y: -clipper.y
            width: root.width
            height: root.height

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                asynchronous: true

                ShapePath {
                    strokeColor: root.stroke
                    strokeWidth: root.thickness
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathSvg {
                        // Two alternating bows: a stem, not a ruler line.
                        path: root.horizontal ? `M 0 ${root.bow} Q ${root.width * 0.25} 0 ${root.width * 0.5} ${root.bow} Q ${root.width * 0.75} ${root.bow * 2} ${root.width} ${root.bow}` : `M ${root.bow} ${root.height} Q 0 ${root.height * 0.75} ${root.bow} ${root.height * 0.5} Q ${root.bow * 2} ${root.height * 0.25} ${root.bow} 0`
                    }
                }
            }

            Repeater {
                model: root.leafStops

                Rectangle {
                    required property real modelData
                    required property int index

                    width: root.leafSize
                    height: root.leafSize * 0.62
                    radius: height / 2
                    color: root.leaf
                    x: root.horizontal ? root.width * modelData - width / 2 : root.bow + (index % 2 ? 2 : -2 - width)
                    y: root.horizontal ? root.bow + (index % 2 ? 2 : -2 - height) : root.height * (1 - modelData) - height / 2
                    rotation: index % 2 ? 24 : -24
                    opacity: root.progress > modelData ? 1 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }
            }
        }
    }
}
