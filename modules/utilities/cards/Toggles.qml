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
                        icon: "wifi"
                        checked: Nmcli.wifiEnabled
                        onClicked: Nmcli.toggleWifi()
                    }
                }
                DelegateChoice {
                    roleValue: "bluetooth"
                    delegate: Toggle {
                        label: qsTr("Bluetooth")
                        icon: "bluetooth"
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
                        icon: "mic"
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
                        icon: "mouse"
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
                        icon: "rocket_launch"
                        checked: GameMode.enabled
                        enabled: GameMode.available
                        onClicked: GameMode.toggle()
                    }
                }
                DelegateChoice {
                    roleValue: "breakReminders"
                    delegate: Toggle {
                        label: qsTr("Break reminders")
                        icon: "hourglass_top"
                        checked: Tasks.pomodoro.enabled ?? false
                        enabled: Tasks.integrationEnabled
                        onClicked: Tasks.toggleBreakReminders()
                    }
                }
                DelegateChoice {
                    roleValue: "clockInReminders"
                    delegate: Toggle {
                        label: qsTr("Clock-in reminders")
                        icon: "work_history"
                        checked: Tasks.clockInReminders
                        enabled: Tasks.integrationEnabled
                        onClicked: Tasks.toggleClockInReminders()
                    }
                }
                DelegateChoice {
                    roleValue: "dnd"
                    delegate: Toggle {
                        label: qsTr("Do not disturb")
                        icon: "notifications_off"
                        checked: Notifs.dnd
                        onClicked: Notifs.dnd = !Notifs.dnd
                    }
                }
                DelegateChoice {
                    roleValue: "vpn"
                    delegate: Toggle {
                        label: qsTr("VPN")
                        icon: "vpn_key"
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
