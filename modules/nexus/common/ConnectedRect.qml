import QtQuick
import Burl.Config
import qs.components
import qs.services

StyledRect {
    property bool first
    property bool last

    color: Woodland.surface(Colours.tPalette.m3surfaceContainer, Colours.light)
    topLeftRadius: first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
    topRightRadius: first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
    bottomLeftRadius: last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
    bottomRightRadius: last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
}
