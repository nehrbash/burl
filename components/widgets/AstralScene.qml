pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services

Item {
    id: root
    property string scene: "sky"
    property bool active: true
    property real camera: 0
    property var cameraMotion: null
    property real viewZoom: 1
    property real viewPanX: 0
    property real viewPanY: 0
    // Room changes hide the scenery without restarting its ambient clocks.
    readonly property bool moving: active && visible && (cameraMotion ? cameraMotion.revealP > 0.001 : opacity > 0.001) && Ambience.sway && !GameMode.pauseAnimations
    readonly property bool dream: scene === "dream"
    readonly property bool tree: scene === "tree"
    readonly property bool sky: scene === "sky"
    clip: true
    enabled: false

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#070c1d" }
            GradientStop { position: 0.5; color: "#172435" }
            GradientStop { position: 1; color: "#261c30" }
        }
    }
    Repeater {
        model: root.tree ? 20 : 65
        Rectangle {
            required property int index
            x: ((index * 197 + 37) % 997) / 997 * root.width
            y: ((index * 137 + 81) % 991) / 991 * root.height
            width: index % 4 === 0 ? 2 : 1
            height: width
            color: "#e6ddcf"
            opacity: 0.2 + index % 5 * 0.1
        }
    }

    DepthGroup {
        depth: 0.06
        opacity: 0.8
        fragments: root.sky ? [
            {cell: 6, x: 0.03, y: 0.03, size: 0.17, angle: -24},
            {cell: 7, x: 0.48, y: 0.16, size: 0.07, angle: 28}
        ] : root.tree ? [
            {cell: 7, x: 0.82, y: 0.06, size: 0.11, angle: 18}
        ] : [
            {cell: 6, x: 0.02, y: 0.02, size: 0.31, angle: -12},
            {cell: 7, x: 0.79, y: 0.06, size: 0.13, angle: 18},
            {cell: 4, x: 0.43, y: -0.06, size: 0.2, angle: 13},
            {cell: 1, x: 0.65, y: 0.32, size: 0.16, angle: -17}
        ]
    }
    SpectralClouds {
        anchors.fill: parent
        scene: root.scene
        active: root.moving
        opacity: root.tree ? 0.35 : root.sky ? 0.4 : 0.85
        density: root.tree ? 0.65 : 1.25
        period: root.tree ? 90000 : root.sky ? 36000 : 28000
    }
    CloudBank { visible: !root.tree; cell: 0; baseX: -0.28; baseY: root.sky ? 0.57 : -0.25; span: 0.75; depth: 0.09; opacity: root.sky ? 0.45 : 0.85 }
    CloudBank { visible: !root.tree; cell: 1; baseX: 0.65; baseY: root.sky ? 0.64 : -0.17; span: 0.58; depth: 0.12; opacity: root.sky ? 0.4 : 0.82 }
    DepthGroup {
        depth: 0.17
        opacity: root.tree ? 0.65 : 1
        fragments: root.sky ? [] : root.tree ? [
            {cell: 0, x: -0.16, y: 0.28, size: 0.40, angle: -8},
            {cell: 2, x: 0.84, y: 0.25, size: 0.30, angle: 10}
        ] : [
            {cell: 0, x: -0.11, y: 0.13, size: 0.46, angle: -12},
            {cell: 2, x: 0.75, y: 0.1, size: 0.36, angle: 17},
            {cell: 5, x: 0.61, y: 0.56, size: 0.31, angle: -8}
        ]
    }
    SpectralClouds {
        visible: !root.tree
        x: -root.width * 0.08
        y: root.height * 0.18
        width: root.width * 1.16
        height: root.height
        scene: root.scene
        spilling: true
        active: root.moving
        opacity: root.sky ? 0.35 : 0.95
        density: 1.35
        period: 28000
    }
    CloudBank { cell: 2; baseX: -0.22; baseY: root.sky ? 0.81 : 0.42; span: 0.68; depth: 0.23; opacity: root.tree ? 0.3 : 0.9 }
    CloudBank { cell: 3; baseX: 0.64; baseY: root.sky ? 0.85 : 0.4; span: 0.63; depth: 0.26; opacity: root.tree ? 0.3 : 0.9 }
    DepthGroup {
        depth: 0.3
        fragments: root.sky ? [
            {cell: 1, x: 0.07, y: 0.83, size: 0.13, angle: -8},
            {cell: 4, x: 0.86, y: 0.88, size: 0.11, angle: 12}
        ] : root.tree ? [] : [
            {cell: 3, x: -0.12, y: 0.62, size: 0.42, angle: 8},
            {cell: 1, x: 0.82, y: 0.59, size: 0.31, angle: -24}
        ]
    }
    AstralFragment {
        visible: root.dream
        cell: 8
        width: Math.min(root.width * 0.42, root.height * 0.72)
        height: width
        x: (root.width - width) / 2
        y: root.height * 0.21
        drifting: root.moving
        driftY: 4
    }
    AstralGlass {
        visible: !root.tree
        anchors.fill: parent
        active: root.moving
        opacity: 0.85
    }
    component DepthGroup: Item {
        id: group
        required property real depth
        required property var fragments
        anchors.fill: parent
        Repeater {
            model: group.fragments
            Item {
                id: fragmentCamera
                required property var modelData
                required property int index
                y: -root.camera * root.height * (root.sky ? 0.8 + group.depth : group.depth)
                CameraYBehavior on y { camera: root.cameraMotion }

                AstralFragment {
                    readonly property real parallax: root.sky ? 0.1 + group.depth * 0.3 : 0
                    scale: Math.pow(root.viewZoom, parallax)
                    cell: fragmentCamera.modelData.cell
                    width: root.width * fragmentCamera.modelData.size
                    height: width
                    x: root.width * fragmentCamera.modelData.x + root.viewPanX * parallax
                    y: root.height * fragmentCamera.modelData.y + root.viewPanY * parallax
                    rotation: fragmentCamera.modelData.angle
                    drifting: root.moving
                    driftX: (root.tree ? 0.25 : 1) * (fragmentCamera.index % 2 ? -1 : 1) * (root.sky ? root.width * 0.014 : group.depth * 80)
                    driftY: root.tree ? 3 : root.sky ? root.height * 0.02 : group.depth * 65
                    tilt: root.tree ? 0.4 : group.depth * 9
                    period: (root.tree ? 240000 : 90000) + fragmentCamera.index * 17000 + group.depth * 50000
                }
            }
        }
    }
    component CloudBank: Item {
        id: bank
        required property int cell
        required property real baseX
        required property real baseY
        required property real span
        required property real depth
        readonly property real driftX: root.width * (root.tree ? 0.008 : 0.022) * (cell % 2 ? -1 : 1)
        readonly property real driftY: root.height * (root.tree ? 0.008 : 0.025)
        readonly property int period: (root.tree ? 100000 : 28000) + cell * 2700
        width: root.width * span
        height: width
        x: root.width * baseX
        y: root.height * baseY - root.camera * root.height * (root.sky ? 0.7 + depth : depth)
        CameraYBehavior on y { camera: root.cameraMotion }
        Image {
            id: cloud
            width: bank.width
            height: bank.height
            source: Quickshell.shellPath("assets/images/nocturne/cloud-island.png")
            mirror: bank.cell % 2 === 1
            rotation: bank.cell % 2 === 0 ? -9 : 12
            asynchronous: true
            mipmap: true
        }
        SequentialAnimation {
            running: root.moving && bank.visible
            loops: Animation.Infinite
            XAnimator { target: cloud; from: -bank.driftX; to: bank.driftX; duration: bank.period / 2; easing.type: Easing.InOutSine }
            XAnimator { target: cloud; from: bank.driftX; to: -bank.driftX; duration: bank.period / 2; easing.type: Easing.InOutSine }
        }
        SequentialAnimation {
            running: root.moving && bank.visible
            loops: Animation.Infinite
            YAnimator { target: cloud; from: bank.driftY; to: -bank.driftY; duration: bank.period * 0.4; easing.type: Easing.InOutSine }
            YAnimator { target: cloud; from: -bank.driftY; to: bank.driftY; duration: bank.period * 0.4; easing.type: Easing.InOutSine }
        }
        SequentialAnimation {
            running: root.moving && bank.visible
            loops: Animation.Infinite
            ScaleAnimator { target: cloud; from: 0.965; to: 1.035; duration: bank.period / 4; easing.type: Easing.InOutSine }
            ScaleAnimator { target: cloud; from: 1.035; to: 0.965; duration: bank.period / 4; easing.type: Easing.InOutSine }
        }
    }
}
