pragma ComponentBehavior: Bound

import QtQuick
import Burl.Config
import qs.services

Text {
    id: root

    property bool animate: false
    readonly property bool folio: {
        let ancestor = parent;
        while (ancestor) {
            if (ancestor.bookSurface !== undefined)
                return ancestor.bookSurface;
            ancestor = ancestor.parent;
        }
        return false;
    }

    // Distance fields preserve glyph edges when the book scales its contents.
    renderType: root.folio || style !== Text.Normal ? Text.QtRendering : Text.NativeRendering
    textFormat: Text.PlainText
    color: Colours.palette.m3onSurface
    font: Tokens.font.body.small

    Behavior on color {
        CAnim {}
    }

    Behavior on text {
        enabled: root.animate

        SequentialAnimation {
            Anim {
                target: root
                property: "opacity"
                to: 0
                type: Anim.FastEffects
            }
            PropertyAction {}
            Anim {
                target: root
                property: "opacity"
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }
}
