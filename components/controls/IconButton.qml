import QtQuick
import Burl.Config
import qs.components
import qs.services

ButtonBase {
    id: root

    property alias icon: label.text
    readonly property alias label: label

    font: Tokens.font.icon.medium
    padding: type === IconButton.Text ? Tokens.padding.extraSmall / 2 : Tokens.padding.small

    activeColour: type === IconButton.Filled ? Woodland.brass : Woodland.brass
    inactiveColour: {
        if (!isToggle && type === IconButton.Filled)
            return Woodland.brass;
        return type === IconButton.Filled ? Colours.tPalette.m3surfaceContainer : Woodland.velvet;
    }
    activeOnColour: type === IconButton.Filled ? Woodland.midnight : type === IconButton.Tonal ? Woodland.midnight : Woodland.brass
    inactiveOnColour: {
        if (!isToggle && type === IconButton.Filled)
            return Woodland.midnight;
        return type === IconButton.Tonal ? Woodland.ivory : Colours.palette.m3onSurfaceVariant;
    }

    implicitWidth: implicitHeight
    implicitHeight: {
        // Ensure even size so icon is centered properly
        const h = label.implicitHeight + padding * 2;
        if (h % 2 !== 0)
            return h + 1;
        return h;
    }

    MaterialIcon {
        id: label

        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1 // Material Symbols glyphs render off-center; empirical fix
        color: root.onColour
        fontStyle: root.font
        fill: !root.isToggle || root.internalChecked ? 1 : 0

        Behavior on fill {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
