import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.services

StyledRect {
    id: root

    default property alias content: contentColumn.data
    property real contentSpacing: Tokens.spacing.largeIncreased
    property bool alignTop: false

    Layout.fillWidth: true
    implicitHeight: contentColumn.implicitHeight + Tokens.padding.large * 2

    radius: Tokens.rounding.medium
    color: Colours.transparency.enabled ? Colours.layer(Colours.palette.m3surfaceContainer, 2) : Colours.palette.m3surfaceContainerHigh

    ColumnLayout {
        id: contentColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: root.alignTop ? parent.top : undefined
        anchors.verticalCenter: root.alignTop ? undefined : parent.verticalCenter
        anchors.margins: Tokens.padding.large

        spacing: root.contentSpacing
    }
}
