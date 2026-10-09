import QtQuick
import QtQuick.Templates
import Burl.Config
import qs.components
import qs.services

TextField {
    id: root

    implicitWidth: contentWidth + leftPadding + rightPadding
    implicitHeight: contentHeight + topPadding + bottomPadding

    color: Colours.palette.m3onSurface
    placeholderTextColor: Colours.palette.m3onSurfaceVariant // No anim cause placeholder is custom
    selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
    selectedTextColor: color

    font: Tokens.font.body.small
    renderType: echoMode === TextField.Password ? TextField.QtRendering : TextField.NativeRendering
    cursorVisible: !readOnly
    verticalAlignment: TextInput.AlignVCenter

    cursorDelegate: Item {}

    Behavior on color {
        CAnim {}
    }

    Behavior on selectionColor {
        CAnim {}
    }

    StyledRect {
        id: cursor

        property bool disableBlink

        x: root.cursorRectangle.x
        y: root.cursorRectangle.y
        implicitWidth: 1.5
        implicitHeight: root.cursorRectangle.height

        color: Colours.palette.m3primary
        radius: Tokens.rounding.large

        Connections {
            function onCursorPositionChanged(): void {
                if (root.activeFocus && root.cursorVisible) {
                    cursor.opacity = 1;
                    cursor.disableBlink = true;
                    enableBlink.restart();
                }
            }

            target: root
        }

        Timer {
            id: enableBlink

            interval: 500
            onTriggered: cursor.disableBlink = false
        }

        // `root.visible` is load-bearing: activeFocus survives the field's
        // window being hidden, and panels that stay mounted while closed
        // (the launcher preloads Content 4s after start, never unmounting it)
        // would keep blinking off-screen. Each blink drives cursor.opacity
        // through the Behavior below, dirtying a node in the full-screen
        // qs-drawers window and forcing sync+render at vsync — measured
        // ~75fps and ~8% CPU burnt at idle on two monitors, identical frames.
        Timer {
            running: root.visible && root.activeFocus && root.cursorVisible && !cursor.disableBlink
            repeat: true
            triggeredOnStart: true
            interval: 500
            onTriggered: parent.opacity = parent.opacity === 1 ? 0 : 1
        }

        Binding {
            when: !root.visible || !root.activeFocus || !root.cursorVisible
            cursor.opacity: 0
        }

        Behavior on x {
            Anim {
                easing.bezierCurve: [0.2, 1, 0.21, 1, 1, 1] // Damped variant of fast spatial curve
                duration: Tokens.anim.durations.expressiveFastEffects
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }
    }
}
