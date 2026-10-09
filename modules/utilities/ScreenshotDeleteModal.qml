pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

// Confirm-delete for a screenshot. Same shape as RecordingDeleteModal, minus
// its two corner ShapePath gradients: one scrim rectangle is enough, and a
// second Shape per overlay buys nothing at 240Hz.
//
// Nothing here has to clear the preview overlay afterwards — the preview is
// anchored by PATH (services/Screenshots.qml), so the rebuild that follows the
// delete drops previewIndex to -1 on its own.
Loader {
    id: root

    required property var props
    required property matrix4x4 deformMatrix

    asynchronous: true
    anchors.fill: parent

    opacity: root.props.screenshotConfirmDelete ? 1 : 0
    active: opacity > 0

    sourceComponent: MouseArea {
        id: confirmation

        property string path

        Component.onCompleted: path = root.props.screenshotConfirmDelete

        hoverEnabled: true
        onClicked: root.props.screenshotConfirmDelete = ""

        StyledRect {
            anchors.fill: parent
            anchors.margins: -Tokens.padding.large
            anchors.rightMargin: -Tokens.padding.large - Config.border.thickness - parent.width * (1 - root.deformMatrix.m11) / 2
            anchors.bottomMargin: -Tokens.padding.large - Config.border.thickness - parent.height * 0.1

            topLeftRadius: Tokens.rounding.extraLarge
            color: Colours.palette.m3scrim
            opacity: 0.5
        }

        StyledRect {
            anchors.centerIn: parent

            width: Math.min(parent.width - Tokens.padding.extraLargeIncreased, implicitWidth)
            implicitWidth: confirmLayout.implicitWidth + Tokens.padding.extraExtraLarge
            implicitHeight: confirmLayout.implicitHeight + Tokens.padding.extraExtraLarge

            radius: Tokens.rounding.extraLarge
            color: Colours.palette.m3surfaceContainerHigh
            scale: 0

            Component.onCompleted: scale = Qt.binding(() => root.props.screenshotConfirmDelete ? 1 : 0)

            WoodPanel {
                anchors.fill: parent
                radius: Tokens.rounding.extraLarge
                framed: true
            }

            MouseArea {
                anchors.fill: parent
            }

            Elevation {
                anchors.fill: parent
                radius: parent.radius
                z: -1
                level: 3
            }

            ColumnLayout {
                id: confirmLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large * 1.5
                spacing: Tokens.spacing.medium

                StyledText {
                    text: qsTr("Delete screenshot?")
                    font: Tokens.font.body.large
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Screenshot '%1' will be permanently deleted.").arg(confirmation.path)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                RowLayout {
                    Layout.topMargin: Tokens.spacing.medium
                    Layout.alignment: Qt.AlignRight
                    spacing: Tokens.spacing.medium

                    TextButton {
                        text: qsTr("Cancel")
                        type: TextButton.Text
                        onClicked: root.props.screenshotConfirmDelete = ""
                    }

                    TextButton {
                        text: qsTr("Delete")
                        type: TextButton.Text
                        onClicked: {
                            Screenshots.remove(root.props.screenshotConfirmDelete);
                            root.props.screenshotConfirmDelete = "";
                        }
                    }
                }
            }

            Behavior on scale {
                Anim {}
            }
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
