import QtQuick
import QtQuick.Shapes
import qs.components

Item {
    id: root

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.alpha(Woodland.barkEdge, 0.85)
            strokeWidth: 2
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: root.width; y2: root.height
                GradientStop { position: 0; color: Woodland.mix(Woodland.barkLit, Woodland.parchmentEdge, 0.28) }
                GradientStop { position: 0.35; color: Woodland.barkShaded }
                GradientStop { position: 0.65; color: Woodland.barkEdge }
                GradientStop { position: 1; color: Woodland.mix(Woodland.barkLit, Woodland.parchmentEdge, 0.16) }
            }
            startX: root.width * 0.48; startY: 0
            PathCubic { x: root.width * 0.98; y: root.height * 0.48; control1X: root.width * 1.05; control1Y: root.height * 0.05; control2X: root.width * 0.92; control2Y: root.height * 0.20 }
            PathCubic { x: root.width * 0.53; y: root.height; control1X: root.width * 1.04; control1Y: root.height * 0.79; control2X: root.width * 0.78; control2Y: root.height * 0.96 }
            PathCubic { x: root.width * 0.02; y: root.height * 0.46; control1X: root.width * 0.10; control1Y: root.height * 0.92; control2X: root.width * 0.03; control2Y: root.height * 0.79 }
            PathCubic { x: root.width * 0.48; y: 0; control1X: root.width * 0.08; control1Y: root.height * 0.22; control2X: root.width * 0.02; control2Y: root.height * 0.08 }
        }
    }
    Rectangle {
        x: root.width * 0.105; y: 5
        width: root.width * 0.79
        height: root.height - 11
        radius: width * 0.48
        border.color: Qt.alpha(Woodland.barkEdge, 0.8)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(Woodland.barkEdge, 2.4) }
            GradientStop { position: 0.55; color: Qt.darker(Woodland.barkEdge, 1.6) }
            GradientStop { position: 1; color: Woodland.barkShaded }
        }
    }
}
