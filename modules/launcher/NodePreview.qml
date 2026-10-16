pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Burl.Config
import qs.components
import qs.services
import "NodePreview.js" as Preview

Rectangle {
    id: root

    property var node: null
    property real discDiameter: 0
    property bool actionsAvailable: false
    property bool primaryAvailable: true
    property bool emacsEnabled: true
    readonly property var descriptor: Preview.describe(node, {
        actionsAvailable: root.actionsAvailable,
        primaryAvailable: root.primaryAvailable,
        emacsEnabled: root.emacsEnabled
    })
    readonly property real textInset: discDiameter > 0 ? discDiameter + 18 : 42

    implicitWidth: 360 + discDiameter
    implicitHeight: Math.max(140, content.implicitHeight + 48)
    radius: height / 2
    color: Woodland.velvet
    border.color: Colours.palette.m3primary
    border.width: 1.5

    Rectangle {
        anchors.fill: parent
        anchors.margins: 5
        radius: height / 2
        color: "transparent"
        border.color: Qt.alpha(Colours.palette.m3primary, 0.28)
    }

    Item {
        visible: root.discDiameter > 0
        width: root.discDiameter + 12
        height: width
        x: -6
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: Qt.alpha(Colours.palette.m3primary, 0.65)
        }
        Repeater {
            model: 32
            Item {
                required property int index
                anchors.fill: parent
                rotation: index * 360 / 32
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: -2
                    width: index % 4 === 0 ? 3 : 1
                    height: index % 4 === 0 ? 8 : 4
                    color: Qt.alpha(Colours.palette.m3primary, index % 4 === 0 ? 0.8 : 0.4)
                }
            }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.alpha(Colours.palette.m3primary, 0.55)
            strokeWidth: 1
            fillColor: "transparent"
            startX: root.textInset
            startY: 16
            PathCubic { x: root.textInset + 38; y: 16; control1X: root.textInset + 18; control1Y: 4; control2X: root.textInset + 22; control2Y: 28 }
            PathLine { x: root.width - root.radius; y: 16 }
            PathCubic { x: root.width - root.radius + 24; y: 23; control1X: root.width - root.radius + 38; control1Y: 16; control2X: root.width - root.radius + 34; control2Y: 40 }
            PathCubic { x: root.width - root.radius + 30; y: 23; control1X: root.width - root.radius + 14; control1Y: 10; control2X: root.width - root.radius + 46; control2Y: 11 }
        }
        ShapePath {
            strokeColor: Qt.alpha(Colours.palette.m3primary, 0.35)
            strokeWidth: 1
            fillColor: "transparent"
            startX: root.textInset + 12
            startY: root.height - 16
            PathCubic { x: root.textInset + 42; y: root.height - 16; control1X: root.textInset + 22; control1Y: root.height - 26; control2X: root.textInset + 32; control2Y: root.height - 6 }
            PathLine { x: root.width - root.radius; y: root.height - 16 }
        }
    }

    Rectangle {
        x: root.width - 24
        anchors.verticalCenter: parent.verticalCenter
        width: 7
        height: 7
        rotation: 45
        color: "transparent"
        border.color: Colours.palette.m3primary
    }

    component PreviewText: StyledText {
        // Distance fields stay sharp under the graph's camera transform.
        renderType: Text.QtRendering
        font.pixelSize: 12
        color: Colours.palette.m3onSurfaceVariant
    }

    Column {
        id: content

        x: root.textInset
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.width - x - 48)
        spacing: 5

        PreviewText {
            width: parent.width
            visible: text.length > 0
            text: root.descriptor.kind
            color: Colours.palette.m3primary
            elide: Text.ElideRight
        }

        PreviewText {
            width: parent.width
            text: root.descriptor.title
            color: Colours.palette.m3onSurface
            font.pixelSize: 18
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Repeater {
            model: root.descriptor.details
            PreviewText {
                required property string modelData
                width: content.width
                text: modelData
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideMiddle
            }
        }

        PreviewText {
            width: parent.width
            visible: text.length > 0
            text: root.descriptor.hint
            wrapMode: Text.WordWrap
        }
    }
}
