pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.components
import qs.components.widgets
import qs.services

Item {
    id: root

    // 0 = looking at the tree, 1 = up in the sky. Driven by Content.
    required property real panP
    property real viewZoom: 1
    property real viewPanX: 0
    property real viewPanY: 0

    // Clearance includes limbs and glow extending above the tree host.
    readonly property real treeH: root.height
    readonly property real panRange: root.height * 1.12
    readonly property real hostY: root.panRange * root.panP
    readonly property real travel: root.panRange * (1 - root.panP)

    readonly property color nightHigh: "#060810"
    readonly property color nightMid: "#12131f"
    readonly property color nightLow: "#231a27"
    readonly property color starlight: Woodland.parchment
    readonly property color moonlight: Woodland.parchmentMid

    // Content keeps the launcher mounted for life so reopens are instant, so
    // NOTHING here may cost anything while it is shut. Driven by Content
    // rather than derived from `panP`: panP 0 is a legitimate place to BE
    // (down at the tree, via Ctrl+Down or the crown hotspot), so gating the
    // sky on the pan made descending indistinguishable from closing.
    required property bool onScreen

    clip: true
    visible: root.onScreen

    // ---- 1. the void ------------------------------------------------------
    // Full-screen and static: the gradient IS the camera's ambient, so panning
    // it would just make the darkness slide, which reads as a bug.
    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            orientation: Gradient.Vertical

            GradientStop {
                position: 0.0
                color: root.nightHigh
            }

            GradientStop {
                position: 0.45
                color: root.nightMid
            }

            // Three intermediate stops on a smoothstep between the mid blue
            // and the warm horizon. A single linear leg put a visible
            // horizontal seam a fifth up from the bottom — not banding in the
            // gradient itself, but the eye catching the derivative change at
            // the stop.
            GradientStop {
                position: 0.60
                color: Woodland.mix(root.nightMid, root.nightLow, 0.18)
            }

            GradientStop {
                position: 0.75
                color: Woodland.mix(root.nightMid, root.nightLow, 0.5)
            }

            GradientStop {
                position: 0.88
                color: Woodland.mix(root.nightMid, root.nightLow, 0.82)
            }

            GradientStop {
                position: 1.0
                color: root.nightLow
            }
        }
    }

    AstralScene {
        anchors.fill: parent
        scene: "sky"
        viewZoom: root.viewZoom
        viewPanX: root.viewPanX
        viewPanY: root.viewPanY
        camera: 1 - root.panP
        visible: root.panP > 0.001
        active: root.onScreen && root.panP > 0.001
    }

    LunarMoon {
        active: root.onScreen && root.panP > 0.001
        readonly property real depth: 0.8
        x: root.width * 0.72 - width * 0.5 + root.viewPanX * 0.09
        y: root.height * 0.13 - depth * root.travel + root.viewPanY * 0.09
        scale: Math.pow(root.viewZoom, 0.16)
        width: Math.max(180, root.height * 0.36)
        height: width
    }

    // ---- 4. one meteor ----------------------------------------------------
    // Fires once per open, partway up the pan. A loop would turn a moment into
    // wallpaper; the point is that the sky feels alive exactly when you arrive
    // in it.
    Item {
        id: meteor

        readonly property real span: root.width * 0.42
        readonly property real fromX: root.width * 0.12
        readonly property real fromY: root.height * 0.10
        readonly property real toX: root.width * 0.62
        readonly property real toY: root.height * 0.28

        x: meteor.fromX
        y: meteor.fromY
        width: 2
        height: 2
        opacity: 0
        visible: root.onScreen && Ambience.sway && !GameMode.enabled

        Rectangle {
            // The tail behind the head, rotated to the travel angle. Must derive
            // from the same from/to the animation uses, not a fixed angle, or
            // head and tail desync into a visibly kinked streak. Positive
            // rotation because the bar extends leftward from the head: Qt maps
            // (-1, 0) to (-cos a, -sin a), so a = atan2(dy, dx) aims it back
            // along the path.
            x: -meteor.span
            y: 0
            width: meteor.span
            height: 1.6
            transformOrigin: Item.Right
            rotation: Math.atan2(meteor.toY - meteor.fromY, meteor.toX - meteor.fromX) * 180 / Math.PI

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0.0
                    color: Qt.alpha(root.starlight, 0)
                }

                GradientStop {
                    position: 1.0
                    color: Qt.alpha(root.starlight, 0.85)
                }
            }
        }

        SequentialAnimation {
            id: streak

            // Park the head at the start before it becomes visible: the position
            // animations below break the x/y bindings and leave the meteor at
            // its destination, so a later run would otherwise start there.
            PropertyAction {
                target: meteor
                property: "x"
                value: meteor.fromX
            }

            PropertyAction {
                target: meteor
                property: "y"
                value: meteor.fromY
            }

            NumberAnimation {
                target: meteor
                property: "opacity"
                from: 0
                to: 1
                duration: 140
            }

            ParallelAnimation {
                NumberAnimation {
                    target: meteor
                    property: "x"
                    from: meteor.fromX
                    to: meteor.toX
                    duration: 900
                    easing.type: Easing.InQuad
                }

                NumberAnimation {
                    target: meteor
                    property: "y"
                    from: meteor.fromY
                    to: meteor.toY
                    duration: 900
                    easing.type: Easing.InQuad
                }

                SequentialAnimation {
                    PauseAnimation {
                        duration: 520
                    }

                    NumberAnimation {
                        target: meteor
                        property: "opacity"
                        to: 0
                        duration: 380
                    }
                }
            }
        }

        // Latched, not bound: `panP > 0.45` is true for the whole time the
        // launcher is open, so a plain binding would re-fire the streak on
        // every unrelated re-evaluation.
        property bool armed: true

        Connections {
            function onPanPChanged(): void {
                if (root.panP < 0.05)
                    meteor.armed = true;
                else if (meteor.armed && root.panP > 0.45 && meteor.visible) {
                    meteor.armed = false;
                    streak.restart();
                }
            }

            target: root
        }
    }

    // ---- 5. ground haze ---------------------------------------------------
    // Warm bark light pooling where the tree meets the earth. Pans WITH the
    // tree (depth 1) so the ground leaves the frame together with it.
    Rectangle {
        x: 0
        y: root.hostY + root.treeH * 0.80
        width: root.width
        height: root.height * 0.55

        gradient: Gradient {
            orientation: Gradient.Vertical

            GradientStop {
                position: 0.0
                color: Qt.alpha(Woodland.barkShaded, 0.0)
            }

            GradientStop {
                position: 0.42
                color: Qt.alpha(Woodland.barkShaded, 0.42)
            }

            GradientStop {
                position: 1.0
                color: Qt.alpha(Woodland.barkEdge, 0.85)
            }
        }
    }

}
