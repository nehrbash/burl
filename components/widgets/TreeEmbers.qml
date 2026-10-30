pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.services

Item {
    id: root

    required property var pointAt
    property bool active: false
    property bool animated: true
    property bool repeatBursts: false
    property real emberSize: 5
    property real drift: 7
    property int duration: 2300
    property color ink: Woodland.mix(Woodland.parchment, Colours.palette.m3primary, 0.35)
    property real travel: 1.3
    readonly property bool motionAllowed: visible && animated && Ambience.grow && !GameMode.pauseAnimations
    readonly property bool running: procession.running
    signal arrived()

    function ignite(): void {
        if (motionAllowed) procession.restart();
    }

    onActiveChanged: {
        if (active) ignite();
        else procession.stop();
    }
    onMotionAllowedChanged: {
        if (!motionAllowed) procession.stop();
        else if (active) ignite();
    }

    Timer {
        interval: root.duration + 2100
        running: root.motionAllowed && root.active && root.repeatBursts
        repeat: true
        onTriggered: root.ignite()
    }

    SequentialAnimation {
        id: procession
        NumberAnimation { target: root; property: "travel"; from: 0; to: 1.3; duration: root.duration; easing.type: Easing.InOutSine }
        ScriptAction { script: root.arrived() }
    }

    Repeater {
        model: 11
        delegate: Item {
            id: ember
            required property int index
            readonly property real t: root.travel - index * 0.025
            readonly property var point: root.pointAt(Math.max(0, Math.min(1, t)))
            x: point.x * root.width - width / 2 + Math.sin(t * 19 + index * 2.4) * root.drift
            y: point.y * root.height - height / 2 + Math.cos(t * 13 + index * 1.7) * root.drift * 0.5
            width: root.emberSize * 5
            height: width
            visible: root.running && t > 0 && t < 1
            opacity: Math.max(0, Math.min(1, t * 10, (1 - t) * 10)) * (1 - index * 0.035)
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: ember.width / 2; centerY: ember.height / 2
                        focalX: centerX; focalY: centerY
                        centerRadius: ember.width / 2
                        GradientStop { position: 0; color: Qt.alpha(root.ink, 0.65) }
                        GradientStop { position: 0.25; color: Qt.alpha(root.ink, 0.25) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    PathAngleArc { centerX: ember.width / 2; centerY: ember.height / 2; radiusX: ember.width / 2; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: root.emberSize * (parent.index % 3 === 0 ? 1 : 0.65)
                height: width
                radius: width / 2
                color: root.ink
            }
        }
    }
}
