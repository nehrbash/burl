pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import Burl.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property PopoutState popouts

    // Carved groove divider: shadow line on parchment, pale scratch on dark bark
    readonly property color groove: Qt.alpha(Colours.light ? Woodland.barkShaded : Woodland.parchmentEdge, 0.4)

    implicitWidth: layout.implicitWidth + Tokens.padding.medium * 2
    implicitHeight: layout.implicitHeight + Tokens.padding.medium * 2

    ButtonGroup {
        id: sinks
    }

    ButtonGroup {
        id: sources
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.medium

        StyledText {
            text: qsTr("Output device")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        Repeater {
            model: Audio.sinks

            StyledRadioButton {
                id: control

                required property PwNode modelData

                ButtonGroup.group: sinks
                checked: Audio.sink?.id === modelData.id
                onClicked: Audio.setAudioSink(modelData)
                text: modelData.description
            }
        }

        // Paired audio devices that aren't connected have no sink yet — offer
        // them alongside the real outputs so picking one wakes the device.
        Repeater {
            model: ScriptModel {
                values: [...Audio.offlineBluetoothSinks].sort((a, b) => a.name.localeCompare(b.name))
            }

            RowLayout {
                id: btSink

                required property BluetoothDevice modelData
                readonly property bool loading: modelData.state === BluetoothDeviceState.Connecting // qmllint disable unresolved-type

                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: Icons.getBluetoothIcon(btSink.modelData.icon)
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: btSink.modelData.name
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                StyledRect {
                    implicitWidth: implicitHeight
                    implicitHeight: connectIcon.implicitHeight + Tokens.padding.extraSmall

                    radius: Tokens.rounding.full
                    color: "transparent"

                    CircularIndicator {
                        anchors.fill: parent
                        running: btSink.loading
                    }

                    StateLayer {
                        disabled: btSink.loading
                        onClicked: Audio.connectBluetoothSink(btSink.modelData)
                    }

                    MaterialIcon {
                        id: connectIcon

                        anchors.centerIn: parent
                        text: "link"
                        color: Colours.palette.m3onSurface
                        opacity: btSink.loading ? 0 : 1

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            implicitHeight: 1
            color: root.groove
        }

        StyledText {
            text: qsTr("Input device")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        Repeater {
            model: Audio.sources

            StyledRadioButton {
                required property PwNode modelData

                ButtonGroup.group: sources
                checked: Audio.source?.id === modelData.id
                onClicked: Audio.setAudioSource(modelData)
                text: modelData.description
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            implicitHeight: 1
            color: root.groove
        }

        StyledText {
            text: qsTr("Volume (%1)").arg(Audio.muted ? qsTr("Muted") : `${Math.round(Audio.volume * 100)}%`)
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        CustomMouseArea {
            Layout.fillWidth: true
            implicitHeight: Tokens.padding.medium * 3

            onWheel: event => {
                if (event.angleDelta.y > 0)
                    Audio.incrementVolume();
                else if (event.angleDelta.y < 0)
                    Audio.decrementVolume();
            }

            StyledSlider {
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: parent.implicitHeight

                value: Audio.volume
                onInteraction: value => Audio.setVolume(value)
            }
        }

        // Per-app mixer, inline. The same sliders live in the Nexus audio page,
        // but "turn that one app down" is a bar-popout errand, not a trip
        // through settings.
        StyledRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            implicitHeight: 1
            color: root.groove
            visible: Audio.streams.length > 0
        }

        StyledText {
            text: qsTr("Apps")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
            visible: Audio.streams.length > 0
        }

        Repeater {
            model: ScriptModel {
                values: [...Audio.streams]
            }

            RowLayout {
                id: stream

                required property PwNode modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: Icons.getVolumeIcon(stream.modelData?.audio?.volume ?? 0, stream.modelData?.audio?.muted ?? false)
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.extraSmall
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.setStreamMuted(stream.modelData, !Audio.getStreamMuted(stream.modelData))
                    }
                }

                StyledText {
                    Layout.maximumWidth: 120
                    text: Audio.getStreamName(stream.modelData)
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }

                StyledSlider {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 90
                    implicitHeight: Tokens.padding.medium * 3

                    enabled: !Audio.getStreamMuted(stream.modelData)
                    value: stream.modelData?.audio?.volume ?? 0
                    onInteraction: v => Audio.setStreamVolume(stream.modelData, v)
                }
            }
        }

        IconTextButton {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            inactiveColour: Colours.palette.m3primaryContainer
            inactiveOnColour: Colours.palette.m3onPrimaryContainer
            verticalPadding: Tokens.padding.extraSmall
            text: qsTr("Open settings")
            icon: "settings"

            onClicked: root.popouts.detachRequested("audio")
        }
    }
}
