pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services

Item {
    id: root

    property real growth: 1
    property bool animated: true
    property real goldMix: 0.82
    property real brightness: 1.12
    property real bend: 0
    property alias phase: treeShader.phase
    property url artSource: Quickshell.shellPath("assets/images/tree/rendered/world-tree-astral.png")
    property url growthSource: Quickshell.shellPath("assets/images/tree/rendered/world-tree-growth.png")

    Image {
        id: wood
        asynchronous: true
        source: root.artSource
        visible: false
        mipmap: true
    }

    Image {
        id: arrival
        asynchronous: true
        source: root.growthSource
        visible: false
    }

    ShaderEffect {
        id: treeShader
        anchors.fill: parent
        property var source: wood
        property var growthMap: arrival
        property real progress: root.growth
        property real phase: 0
        property color accent: Woodland.brass
        property real goldMix: root.goldMix
        property real brightness: root.brightness
        property real bend: root.bend
        fragmentShader: Quickshell.shellPath("assets/shaders/tree-growth.frag.qsb")
    }

    UniformAnimator {
        target: treeShader
        uniform: "phase"
        running: root.visible && root.animated && root.growth > 0.98 && Ambience.sway && !GameMode.enabled
        from: 0
        to: 1
        duration: 12000
        loops: Animation.Infinite
    }
}
