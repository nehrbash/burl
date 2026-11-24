pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import M3Shapes
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.widgets
import qs.services

Item {
    id: root

    required property var auth

    function submit(): void {
        const secret = field.text;
        field.text = "";
        root.auth.submit(secret);
    }

    function cancel(): void {
        field.text = "";
        root.auth.cancel();
    }

    Component.onDestruction: field.text = ""

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Woodland.barkEdge, 0.62)

        MouseArea {
            anchors.fill: parent
        }

        WoodPanel {
            id: panel

            anchors.centerIn: parent
            implicitWidth: Math.min(parent.width - Tokens.padding.large * 4, 460)
            implicitHeight: content.implicitHeight + Tokens.padding.large * 2

            radius: Tokens.rounding.extraLarge
            framed: true
            fill: Colours.palette.m3surfaceContainer

            ColumnLayout {
                id: content

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 72
                    implicitHeight: 72

                    CelestialSeal {
                        anchors.fill: parent
                        star: false
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "lock"
                        color: Woodland.brass
                        fontStyle: Tokens.font.icon.builders.extraLarge.build()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.auth.title
                    color: Woodland.creamPrimary
                    font: Tokens.font.title.medium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.auth.body
                    color: Woodland.creamSecondary
                    font: Tokens.font.body.small
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.auth.detail
                    color: Woodland.creamSecondary
                    opacity: 0.7
                    font: Tokens.font.label.small
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: field.implicitHeight + Tokens.padding.large

                    color: Colours.palette.m3surfaceContainerLowest
                    radius: 10
                    border.width: 1
                    border.color: root.auth.error ? Colours.palette.m3error : Woodland.brass

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.extraSmall
                        spacing: Tokens.spacing.medium

                        TextFieldBase {
                            id: field

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            leftPadding: Tokens.padding.medium
                            focus: true
                            echoMode: root.auth.echo ? TextInput.Normal : TextInput.Password
                            passwordCharacter: "•"
                            font: Tokens.font.body.medium
                            enabled: !root.auth.busy
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

                            Component.onCompleted: forceActiveFocus()
                            onEnabledChanged: if (enabled)
                                forceActiveFocus()
                            onAccepted: root.submit()
                            Keys.onEscapePressed: root.cancel()

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                x: field.leftPadding
                                visible: !field.text
                                text: root.auth.inputPrompt
                                color: Woodland.creamSecondary
                                font: field.font
                            }
                        }

                        Item {
                            implicitWidth: implicitHeight
                            implicitHeight: 32

                            LoadingIndicator {
                                anchors.centerIn: parent
                                visible: root.auth.busy
                                implicitSize: parent.height - Tokens.padding.small * 2
                            }

                            MaterialShape {
                                anchors.fill: parent
                                visible: !root.auth.busy
                                color: field.text ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                                shape: field.text ? MaterialShape.Arrow : MaterialShape.Circle
                                scale: !field.text ? 1 : enterMouse.pressed ? 0.6 : enterMouse.containsMouse ? 0.8 : 0.7
                                rotation: 90

                                Behavior on scale {
                                    Anim {
                                        type: Anim.FastSpatial
                                    }
                                }

                                Behavior on color {
                                    CAnim {}
                                }

                                MouseArea {
                                    id: enterMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: field.text ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: field.text && root.submit()
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.auth.error
                    color: root.auth.errorIsError ? Colours.palette.m3error : Woodland.creamSecondary
                    font: Tokens.font.body.small
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Tokens.spacing.medium

                    TextButton {
                        type: ButtonBase.Text
                        text: qsTr("Cancel")
                        onClicked: root.cancel()
                    }

                    TextButton {
                        text: qsTr("Authenticate")
                        enabled: !root.auth.busy
                        onClicked: root.submit()
                    }
                }
            }
        }
    }
}
