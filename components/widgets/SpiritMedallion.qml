pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Burl
import Burl.Config
import qs.components
import qs.services

Item {
    id: root

    property color accent: Colours.palette.m3primary
    property string glyph: "circle"
    property bool prominent: false
    property bool selected: false
    property bool hovered: false
    property bool animate: true
    property real glowStrength: 1
    property real pulse: 0
    property real breath: 0
    property int phase: 0

    readonly property color ivory: Woodland.mix(Woodland.parchment, root.accent, 0.25)
    readonly property real energy: (selected || hovered ? 0.85 : prominent ? 0.65 : 0.20) + pulse*0.5

    function ignite(): void {
        if (animate && Ambience.grow && !GameMode.enabled)
            flare.restart();
    }

    SequentialAnimation {
        id: flare

        NumberAnimation { target: root; property: "pulse"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "pulse"; to: 0; duration: 1100; easing.type: Easing.OutCubic }
    }

    SequentialAnimation on breath {
        running: root.visible && root.animate && Ambience.sway && !GameMode.enabled
        loops: Animation.Infinite

        PauseAnimation { duration: root.phase*130 }
        NumberAnimation { from: 0; to: 1; duration: 1800+root.phase*170; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 2400+root.phase*170; easing.type: Easing.InOutSine }
    }

    Shape {
        anchors.centerIn: parent
        opacity: root.glowStrength * (0.9 + root.breath * 0.1)
        width: root.width*2.6
        height: width
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width*1.3; centerY: root.height*1.3
                focalX: centerX; focalY: centerY
                centerRadius: root.width*1.3
                GradientStop { position: 0; color: Qt.alpha(root.accent, root.energy*0.36) }
                GradientStop { position: 0.3; color: Qt.alpha(root.accent, root.energy*0.15) }
                GradientStop { position: 0.65; color: Qt.alpha(root.accent, root.energy*0.03) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathAngleArc { centerX: root.width*1.3; centerY: root.height*1.3; radiusX: root.width*1.3; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.width*0.12
        radius: width/2
        color: Woodland.mix(Woodland.barkEdge, Colours.palette.m3surface, 0.55)
        border.color: Qt.alpha(root.ivory, 0.35+root.energy*0.3)
        border.width: root.prominent ? 2 : 1
        scale: 1+root.pulse*0.045
    }

    Shape {
        id: rings

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        rotation: root.phase*37

        RotationAnimation on rotation {
            running: root.visible && root.animate && Ambience.sway && !GameMode.enabled
            from: root.phase*37
            to: root.phase*37+360
            duration: 22000+root.phase*1700
            loops: Animation.Infinite
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.alpha(root.ivory, Math.min(1, 0.52+root.energy*0.4))
            strokeWidth: root.selected ? 2.2 : 1.25
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width/2; centerY: root.height/2; radiusX: root.width*0.44; radiusY: radiusX; startAngle: 12; sweepAngle: 252 }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.alpha(root.accent, Math.min(1, 0.45+root.energy*0.4))
            strokeWidth: 1.5
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width/2; centerY: root.height/2; radiusX: root.width*0.49; radiusY: radiusX; startAngle: 110; sweepAngle: 128 }
        }
    }

    Repeater {
        model: 8

        delegate: Rectangle {
            required property int index

            readonly property real angle: (index*45+root.phase*7)*Math.PI/180
            x: root.width/2+Math.cos(angle)*root.width*0.33-width/2
            y: root.height/2+Math.sin(angle)*root.height*0.33-height/2
            width: index%2 ? 1 : 2
            height: index%2 ? 2 : 3
            rotation: index*45
            radius: 1
            color: root.ivory
            opacity: 0.3+root.energy*0.3
        }
    }

    MaterialIcon {
        anchors.centerIn: parent
        text: root.glyph
        color: root.prominent ? Woodland.mix(root.accent, Woodland.parchment, 0.35) : root.ivory
        fontStyle: root.prominent ? Tokens.font.icon.size(Math.max(17, root.width * 0.285)).build() : Tokens.font.icon.small
        scale: 1+root.pulse*0.12+root.breath*0.025
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.width*(1+root.pulse*0.5)
        height: width
        radius: width/2
        color: "transparent"
        border.color: Qt.alpha(root.accent, root.pulse*0.5)
        border.width: 1
        visible: root.pulse > 0.01
    }
}
