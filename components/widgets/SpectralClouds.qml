import QtQuick
import Quickshell
import qs.components
import qs.services

Item {
    id: root
    property string scene: "dream"
    property bool active: true
    property alias phase: cloudShader.phase
    readonly property bool animating: playback.running
    property bool spilling: false
    property real density: 1
    property int period: scene === "tree" ? 24000 : scene === "sky" ? 36000 : 28000
    readonly property bool ready: atlas.status === Image.Ready
    readonly property bool moving: root.active && root.visible && root.opacity > 0.001
        && root.ready && Ambience.sway && !GameMode.enabled

    Image {
        id: atlas
        source: Quickshell.shellPath("assets/images/nocturne/" + (root.spilling ? "veil" : root.scene) + "-clouds.png")
        asynchronous: true
        visible: false
    }
    ShaderEffect {
        id: cloudShader
        anchors.fill: parent
        visible: root.ready
        property var source: atlas
        property real phase: 0
        property real density: root.density
        fragmentShader: Quickshell.shellPath("assets/shaders/spectral-clouds.frag.qsb")
    }
    UniformAnimator {
        id: playback
        target: cloudShader
        uniform: "phase"
        from: 0
        to: 1
        duration: root.period
        loops: Animation.Infinite
        running: root.moving
    }
}
