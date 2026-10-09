import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.services

ButtonBase {
    id: root

    property alias icon: iconLabel.text
    property alias text: label.text

    readonly property alias iconLabel: iconLabel
    readonly property alias label: label

    horizontalPadding: Tokens.padding.medium
    verticalPadding: Tokens.padding.small

    implicitWidth: row.implicitWidth + horizontalPadding * 2
    implicitHeight: row.implicitHeight + verticalPadding * 2

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        MaterialIcon {
            id: iconLabel

            Layout.alignment: Qt.AlignVCenter
            color: root.onColour
            fill: root.internalChecked ? 1 : 0
            fontStyle: {
                const f = Qt.font(root.font);
                f.pointSize = Math.round(root.font.pointSize * 1.2);
                return f;
            }

            Behavior on fill {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        StyledText {
            id: label

            Layout.alignment: Qt.AlignVCenter
            Layout.topMargin: 1
            color: root.onColour
            font: root.font
        }
    }
}
