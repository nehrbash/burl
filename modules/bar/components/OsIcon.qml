import QtQuick
import Quickshell
import qs.components
import qs.components.widgets
import qs.services
import Burl.Config

Item {
    id: root

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: implicitWidth * 1.3
    property real response: 0
    property real headTilt: 0

    function acknowledge(): void {
        response = 1;
        reply.restart();
        if (Ambience.sway && !GameMode.enabled) nod.restart();
    }

    MouseArea {
        id: pointer
        z: 1
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.acknowledge()
        onClicked: {
            const screenState = ShellState.forActive();
            if (GlobalConfig.dashboard.navStyle === "living")
                screenState.toggleWorldRoom("launcher");
            else
                screenState.launcher = !screenState.launcher;
        }
    }

    CelestialSeal {
        anchors.centerIn: parent
        width: parent.width * (0.75 + root.response * 0.22)
        height: width
        star: false
        ink: Woodland.ivory
        opacity: root.response * 0.95 + (pointer.containsMouse ? 0.25 : 0)
        rotation: root.response * 35
    }

    Image {
        anchors.centerIn: parent
        width: parent.width * 1.02
        height: parent.height * 1.02
        source: Quickshell.shellPath("assets/images/nocturne/companions.png")
        sourceClipRect: Qt.rect(0, 140, 313.5, 480)
        fillMode: Image.PreserveAspectFit
        mipmap: true
        rotation: root.headTilt
        scale: pointer.pressed ? 0.92 : pointer.containsMouse ? 1.08 : 1
        Behavior on scale { NumberAnimation { duration: Ambience.grow ? 130 : 0; easing.type: Easing.OutCubic } }
    }

    NumberAnimation {
        id: reply
        target: root
        property: "response"
        from: 1
        to: 0
        duration: 950
        easing.type: Easing.OutCubic
    }
    SequentialAnimation {
        id: nod
        NumberAnimation { target: root; property: "headTilt"; to: -9; duration: 90 }
        NumberAnimation { target: root; property: "headTilt"; to: 6; duration: 160 }
        NumberAnimation { target: root; property: "headTilt"; to: 0; duration: 200; easing.type: Easing.OutCubic }
    }
}
