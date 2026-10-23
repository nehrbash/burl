pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Bluetooth
import Burl.Components
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.widgets
import qs.components.effects
import qs.services
import qs.modules.bar.popouts as BarPopouts

StyledRect {
    id: root

    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts

    readonly property var quickToggles: {
        const seenIds = new Set();

        return Config.utilities.quickToggles.filter(item => {
            if (!(item.enabled ?? true))
                return false;

            if (seenIds.has(item.id)) {
                return false;
            }

            seenIds.add(item.id);

            if (item.id === "vpn")
                return GlobalConfig.utilities.vpn.provider.some(p => typeof p === "object" ? (p.enabled === true) : false);

            return true;
        });
    }
    readonly property int splitIndex: Math.ceil(quickToggles.length / 2)
    readonly property bool needExtraRow: quickToggles.length > 6

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + Tokens.padding.extraLargeIncreased

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    WoodPanel {
        anchors.fill: parent
    }

    BarkFrame {
        anchors.fill: parent
        radius: parent.radius
        frameWidth: 3
    }

    CelestialSeal {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        width: 22
        height: width
        opacity: 0.75
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        StyledText {
            text: qsTr("Quick Toggles")
            font: Tokens.font.body.medium
        }

        QuickToggleRow {
            model: root.needExtraRow ? root.quickToggles.slice(0, root.splitIndex) : root.quickToggles
        }

        QuickToggleRow {
            visible: root.needExtraRow
            model: root.needExtraRow ? root.quickToggles.slice(root.splitIndex) : []
        }
    }

    component QuickToggleRow: ButtonRow {
        property alias model: repeater.model

        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            id: repeater

            delegate: DelegateChooser {
                role: "id"

                DelegateChoice {
                    roleValue: "wifi"
                    delegate: Toggle {
                        label: qsTr("Wi-Fi")
                        activeIcon: "wifi"
                        inactiveIcon: "wifi_off"
                        checked: Nmcli.wifiEnabled
                        onClicked: Nmcli.toggleWifi()
                    }
                }
                DelegateChoice {
                    roleValue: "bluetooth"
                    delegate: Toggle {
                        label: qsTr("Bluetooth")
                        activeIcon: "bluetooth"
                        inactiveIcon: "bluetooth_disabled"
                        checked: Bluetooth.defaultAdapter?.enabled ?? false // qmllint disable unresolved-type
                        onClicked: {
                            const adapter = Bluetooth.defaultAdapter; // qmllint disable unresolved-type
                            if (adapter)
                                adapter.enabled = !adapter.enabled;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "mic"
                    delegate: Toggle {
                        label: qsTr("Microphone")
                        activeIcon: "mic"
                        inactiveIcon: "mic_off"
                        checked: !Audio.sourceMuted
                        onClicked: {
                            const audio = Audio.source?.audio;
                            if (audio)
                                audio.muted = !audio.muted;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "mouseAcceleration"
                    delegate: Toggle {
                        label: qsTr("Mouse acceleration")
                        activeIcon: "mouse"
                        checked: MouseSettings.accelerationEnabled
                        enabled: MouseSettings.ready && !MouseSettings.busy
                        ToolTip.text: MouseSettings.error || (checked ? qsTr("Adaptive pointer speed") : qsTr("Flat pointer speed"))
                        onClicked: {
                            MouseSettings.toggleAcceleration();
                            internalChecked = checked;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "gameMode"
                    delegate: Toggle {
                        label: qsTr("Performance mode")
                        activeIcon: "rocket_launch"
                        checked: GameMode.enabled
                        enabled: GameMode.available
                        onClicked: GameMode.toggle()
                    }
                }
                DelegateChoice {
                    roleValue: "breakReminders"
                    delegate: Toggle {
                        label: qsTr("Break reminders")
                        activeIcon: "timer"
                        inactiveIcon: "timer_off"
                        checked: Tasks.pomodoro.enabled ?? false
                        enabled: Tasks.integrationEnabled
                        onClicked: Tasks.toggleBreakReminders()
                    }
                }
                DelegateChoice {
                    roleValue: "clockInReminders"
                    delegate: Toggle {
                        label: qsTr("Clock-in reminders")
                        activeIcon: "work"
                        inactiveIcon: "work_off"
                        checked: Tasks.clockInReminders
                        enabled: Tasks.integrationEnabled
                        onClicked: Tasks.toggleClockInReminders()
                    }
                }
                DelegateChoice {
                    roleValue: "dnd"
                    delegate: Toggle {
                        label: qsTr("Do not disturb")
                        activeIcon: "do_not_disturb_on"
                        inactiveIcon: "do_not_disturb_off"
                        checked: Notifs.dnd
                        onClicked: Notifs.dnd = !Notifs.dnd
                    }
                }
                DelegateChoice {
                    roleValue: "vpn"
                    delegate: Toggle {
                        label: qsTr("VPN")
                        activeIcon: "vpn_key"
                        inactiveIcon: "vpn_key_off"
                        checked: VPN.connected && VPN.status.state !== "needs-auth" && VPN.status.state !== "error"
                        enabled: !VPN.connecting
                        isToggle: VPN.status.state !== "needs-auth" && VPN.status.state !== "error"
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        onClicked: VPN.toggle()
                    }
                }
            }
        }
    }

    component Toggle: IconButton {
        id: toggle
        required property string activeIcon
        property string inactiveIcon: activeIcon
        icon: checked ? activeIcon : inactiveIcon

        Rectangle {
            anchors.centerIn: parent
            width: 25
            height: 4
            rotation: 45
            visible: !toggle.checked && toggle.activeIcon === toggle.inactiveIcon
            color: toggle.color
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: 2
                color: toggle.onColour
            }
        }
        required property string label
        Accessible.name: label
        ToolTip.text: checked ? qsTr("%1 on").arg(label) : qsTr("%1 off").arg(label)
        ToolTip.visible: hovered
        ToolTip.delay: 500
        inactiveColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
        fillWidth: true
        isToggle: true
        isRound: true
        shapeMorph: true
    }
}
