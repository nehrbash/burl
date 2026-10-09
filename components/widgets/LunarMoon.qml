import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.components
import qs.components.widgets
import qs.services

Item {
    id: root

    property bool active: true
    property real ritualPhase: 0
    readonly property bool moving: active && visible && opacity > 0.001 && Ambience.sway && !GameMode.enabled
    readonly property real glow: 0.5 + 0.5 * Math.sin(ritualPhase * 8)
    property real phase: Weather.moonPhase
    readonly property real litFraction: (1 - Math.cos(phase * Math.PI * 2)) / 2
    visible: phase >= 0
    Component.onCompleted: if (!Weather.cc) Weather.reload()

    Shape {
        anchors.centerIn: parent
        width: root.width * 2.6
        height: width
        preferredRendererType: Shape.CurveRenderer
        opacity: 0.28 + root.litFraction * 0.18 + root.glow * 0.12
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width * 1.3; centerY: centerX
                focalX: centerX; focalY: centerY
                centerRadius: root.width * 1.3
                GradientStop { position: 0; color: "#ad4566" }
                GradientStop { position: 0.3; color: Qt.alpha("#ad4566", 0.3) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathAngleArc {
                centerX: root.width * 1.3; centerY: centerX
                radiusX: root.width * 1.3; radiusY: radiusX
                startAngle: 0; sweepAngle: 360
            }
        }
    }
    CelestialSeal {
        anchors.centerIn: parent
        width: root.width * 1.08
        height: width
        ink: "#edaa79"
        star: false
        opacity: 0.55 + root.glow * 0.2
        rotation: 15 + root.ritualPhase * 180 / Math.PI
    }
    Image {
        id: moonArt
        source: Quickshell.shellPath("assets/images/nocturne/crimson-moon.png")
        asynchronous: true
        mipmap: true
        visible: false
    }
    ShaderEffect {
        anchors.fill: parent
        property var source: moonArt
        property real phase: root.phase
        property real ritualPhase: root.ritualPhase
        fragmentShader: Quickshell.shellPath("assets/shaders/lunar-moon.frag.qsb")
    }
    CelestialSeal {
        anchors.centerIn: parent
        width: root.width * 0.76
        height: width
        ink: "#ffd28e"
        star: false
        opacity: 0.18 + root.glow * 0.16
        rotation: -root.ritualPhase * 360 / Math.PI
    }
    NumberAnimation on ritualPhase {
        from: 0
        to: Math.PI * 2
        duration: 48000
        loops: Animation.Infinite
        running: root.moving
    }
}
