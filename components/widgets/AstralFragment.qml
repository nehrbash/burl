import QtQuick
import Quickshell

Item {
    id: root
    required property int cell
    property bool drifting: false
    property real driftX: 0
    property real driftY: 0
    property real tilt: 0
    property int period: 110000
    enabled: false
    Item {
        id: motion
        width: root.width
        height: root.height
        Image {
            anchors.fill: parent
            sourceClipRect: Qt.rect((root.cell % 3) * 1254, Math.floor(root.cell / 3) * 1254, 1254, 1254)
            source: Quickshell.shellPath("assets/images/nocturne/astral-fragments.png")
            asynchronous: true
            mipmap: true
        }
    }
    SequentialAnimation {
        running: root.drifting
        loops: Animation.Infinite
        XAnimator { target: motion; from: -root.driftX; to: root.driftX; duration: root.period / 2; easing.type: Easing.InOutSine }
        XAnimator { target: motion; from: root.driftX; to: -root.driftX; duration: root.period / 2; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        running: root.drifting
        loops: Animation.Infinite
        YAnimator { target: motion; from: root.driftY; to: -root.driftY; duration: root.period * 0.37; easing.type: Easing.InOutSine }
        YAnimator { target: motion; from: -root.driftY; to: root.driftY; duration: root.period * 0.37; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        running: root.drifting
        loops: Animation.Infinite
        RotationAnimator { target: motion; from: -root.tilt; to: root.tilt; duration: root.period * 0.43; easing.type: Easing.InOutSine }
        RotationAnimator { target: motion; from: root.tilt; to: -root.tilt; duration: root.period * 0.43; easing.type: Easing.InOutSine }
    }
}
