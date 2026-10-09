pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components.containers
import qs.components
import Burl.Config
import qs.services
import qs.utils
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen

    readonly property bool disabled: Strings.testRegexList(Config.bar.excludedScreens, screen.name)
    readonly property int clampedWidth: Math.max(Config.border.minThickness, implicitWidth)
    readonly property int padding: Math.max(Tokens.padding.small, Config.border.thickness)
    readonly property int contentWidth: Tokens.sizes.bar.innerWidth + padding * 2
    readonly property int barkOverhang: 4
    readonly property real trunkWidth: (contentWidth + barkOverhang) * 5.6
    readonly property real trunkX: content.x + contentWidth / 2 - trunkWidth * 0.265
    readonly property bool persistent: Config.bar.persistent && !FocusMode.enabled
    readonly property int exclusiveZone: !disabled && (persistent || screenState.bar) ? contentWidth : Config.border.thickness
    readonly property bool shouldBeVisible: !fullscreen && !disabled && (persistent || screenState.bar || isHovered)
    property bool isHovered

    function closeTray(): void {
        (content.item as Bar)?.closeTray();
    }

    function checkPopout(y: real): void {
        (content.item as Bar)?.checkPopout(y);
    }

    function handleWheel(y: real, angleDelta: point): void {
        (content.item as Bar)?.handleWheel(y, angleDelta);
    }

    visible: width > Config.border.thickness
    implicitWidth: Config.border.thickness

    states: State {
        name: "visible"
        when: root.shouldBeVisible

        PropertyChanges {
            root.implicitWidth: root.contentWidth
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                property: "implicitWidth"
                duration: Tokens.anim.durations.expressiveDefaultSpatial
                easing: Tokens.anim.expressiveDefaultSpatial
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                property: "implicitWidth"
                easing: Tokens.anim.emphasized
            }
        }
    ]

    Rectangle {
        x: content.x - 4
        width: root.contentWidth + 8
        height: parent.height
        visible: content.active
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.28; color: Qt.rgba(0.035, 0.027, 0.021, 0.3) }
            GradientStop { position: 0.5; color: Qt.rgba(0.035, 0.027, 0.021, 0.44) }
            GradientStop { position: 0.72; color: Qt.rgba(0.035, 0.027, 0.021, 0.3) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.rightMargin: -Math.round(root.barkOverhang / 2)

        active: root.shouldBeVisible

        sourceComponent: Bar {
            width: root.contentWidth
            screen: root.screen
            screenState: root.screenState
            popouts: root.popouts // qmllint disable incompatible-type
        }
    }

    // Overhang stays beneath applications but remains whole over Burl's own sky.
    Item {
        anchors.fill: parent
        clip: !(root.screenState.launcher || root.screenState.dashboard)
        z: -1
        SidebarTrunk {
            bar: root
            height: parent.height
        }
    }

    StyledWindow {
        name: "bar-roots"
        screen: root.screen
        visible: root.visible && !ShellState.componentsFor(root.screen)?.background
        anchors.left: true
        anchors.top: true
        anchors.bottom: true
        implicitWidth: root.trunkWidth
        exclusiveZone: 0
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        SidebarTrunk {
            bar: root
            height: parent.height
        }
    }

}
