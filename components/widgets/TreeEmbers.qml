pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.services

Item {
    id: root

    required property var pointAt
    property bool active: false
    property bool animated: true
    property color ink: Colours.palette.m3primary
    property real travel: 1.3
    readonly property bool motionAllowed: visible && animated && Ambience.grow && !GameMode.enabled
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

    SequentialAnimation {
        id: procession
        NumberAnimation { target: root; property: "travel"; from: 0; to: 1.3; duration: 1550; easing.type: Easing.InOutSine }
        ScriptAction { script: root.arrived() }
    }

    Repeater {
        model: 5
        delegate: Item {
            required property int index
            readonly property real t: root.travel - index * 0.065
            readonly property var point: root.pointAt(Math.max(0, Math.min(1, t)))
            x: point.x * root.width - width / 2
            y: point.y * root.height - height / 2
            width: 10
            height: 10
            visible: root.running && t > 0 && t < 1
            opacity: Math.sin(Math.PI * Math.max(0, Math.min(1, t))) * (1 - index * 0.13)
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.alpha(root.ink, 0.12)
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.index === 0 ? 3 : 2
                height: width
                radius: width / 2
                color: root.ink
            }
        }
    }
}
