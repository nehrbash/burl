import QtQuick
import Burl.Config
import qs.components
import qs.services

ButtonBase {
    id: root

    property alias text: label.text
    readonly property alias label: label

    horizontalPadding: Tokens.padding.medium
    verticalPadding: Tokens.padding.small

    activeColour: type === TextButton.Filled ? Woodland.brass : Woodland.brass
    inactiveColour: {
        if (!isToggle && type === TextButton.Filled)
            return Woodland.brass;
        return type === TextButton.Filled ? Colours.tPalette.m3surfaceContainer : Woodland.velvet;
    }
    activeOnColour: {
        if (type === TextButton.Text)
            return Woodland.brass;
        return type === TextButton.Filled ? Woodland.midnight : Woodland.midnight;
    }
    inactiveOnColour: {
        if (!isToggle && type === TextButton.Filled)
            return Woodland.midnight;
        if (type === TextButton.Text)
            return Woodland.brass;
        return type === TextButton.Filled ? Colours.palette.m3onSurface : Woodland.ivory;
    }

    implicitWidth: label.implicitWidth + horizontalPadding * 2
    implicitHeight: label.implicitHeight + verticalPadding * 2

    StyledText {
        id: label

        anchors.centerIn: parent
        color: root.onColour
        font: root.font
    }
}
