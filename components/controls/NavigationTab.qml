import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import Burl.Config
import qs.components
import qs.services

T.TabButton {
    id: root

    property string iconName

    implicitWidth: Math.max(72, labelRow.implicitWidth + Tokens.padding.medium * 2)
    implicitHeight: labelRow.implicitHeight + Tokens.padding.medium * 2 + engraving.implicitHeight
    checkable: false
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    padding: Tokens.padding.medium
    bottomPadding: engraving.implicitHeight + Tokens.padding.medium

    background: Rectangle {
        color: Qt.alpha(Colours.palette.m3primary, root.hovered || root.down ? 0.06 : 0)
        border.width: root.activeFocus ? 1 : 0
        border.color: Qt.alpha(Colours.palette.m3primary, 0.5)
    }

    contentItem: Item {
        implicitWidth: labelRow.implicitWidth
        implicitHeight: labelRow.implicitHeight

        RowLayout {
            id: labelRow
            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                visible: !!root.iconName
                text: root.iconName
                color: root.checked ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
            StyledText {
                text: root.text
                font: Tokens.font.body.small
                color: root.checked ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }
        }
    }

    TabEngraving {
        id: engraving
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 3
        selected: root.checked
    }
}
