pragma ComponentBehavior: Bound

import QtQuick
import M3Shapes
import Burl.Config
import qs.components
import qs.components.containers
import qs.services

Item {
    id: root

    readonly property list<int> shapePool: [MaterialShape.Circle, MaterialShape.Cookie4Sided, MaterialShape.Cookie6Sided, MaterialShape.Cookie7Sided, MaterialShape.Cookie9Sided, MaterialShape.Cookie12Sided, MaterialShape.Sunny, MaterialShape.VerySunny, MaterialShape.SoftBurst, MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Arch, MaterialShape.Arrow, MaterialShape.Pill, MaterialShape.Triangle, MaterialShape.Fan, MaterialShape.Oval]
    // Living-tree mode: this Item is the whole Media tab's backdrop, and with
    // no WoodPanel behind it any more there is nothing else to read the
    // transport/lyrics text against. `plate` grows an opaque backing rect
    // (raw `Colours.palette`, not `Colours.tPalette` — the same "skip the
    // shell's global transparency layer" move as BarkCard.opaque) so the
    // drifting shapes keep floating over a plate instead of bare wallpaper.
    property bool plate: false
    readonly property bool folio: backing.folio

    property int count: 14
    property real minSize: 36
    property real maxSize: 124
    property real minSpeed: 4
    property real maxSpeed: 18
    property real minRotSpeed: -12
    property real maxRotSpeed: 12
    property list<real> lightOpacities: [0.34, 0.34, 0.08, 0.2]
    property list<real> darkOpacities: [0.16, 0.16, 0.04, 0.16]

    function rand(min: real, max: real): real {
        return min + Math.random() * (max - min);
    }

    function signedRand(min: real, max: real): real {
        return rand(min, max) * (Math.random() < 0.5 ? -1 : 1);
    }

    clip: true
    Component.onCompleted: shapes.model = count

    // Drawn first (bottom of the stack) so the drifting shapes and, above
    // them, Media.qml's RowLayout both sit on top of it.
    //
    // A bark plate, not a flat Material surface: in living mode this lands on
    // the world tree's parchment scroll, and a plain dark rounded rect on cream
    // paper reads as a widget pasted onto the page. Grain and a carved rim make
    // it a wooden tablet laid on the parchment instead.
    BarkCard {
        id: backing
        anchors.fill: parent
        visible: root.plate
        radius: Tokens.rounding.extraLarge * 2
        grainSeed: 5
        grainHorizontal: true
    }

    Repeater {
        id: shapes

        DriftingShape { visible: !root.folio }
    }

    FrameAnimation {
        running: !root.folio && root.visible && root.width > 0 && root.height > 0 && (Players.active?.isPlaying ?? false)
        onTriggered: {
            const dt = frameTime;
            for (let i = 0; i < shapes.count; i++) {
                const s = shapes.itemAt(i) as DriftingShape;
                if (!s)
                    continue;

                s.x += s.vx * dt;
                s.y += s.vy * dt;
                s.rotation += s.vr * dt;

                if (s.x + s.width < 0)
                    s.x = root.width;
                else if (s.x > root.width)
                    s.x = -s.width;

                if (s.y + s.height < 0)
                    s.y = root.height;
                else if (s.y > root.height)
                    s.y = -s.height;
            }
        }
    }

    component DriftingShape: MaterialShape {
        id: shapeItem

        required property int index

        property real vx: root.signedRand(root.minSpeed, root.maxSpeed)
        property real vy: root.signedRand(root.minSpeed, root.maxSpeed)
        property real vr: root.rand(root.minRotSpeed, root.maxRotSpeed)
        readonly property int colourIdx: Math.floor(Math.random() * 4)

        implicitSize: root.minSize + (index / root.count) * (root.maxSize - root.minSize)
        shape: root.shapePool[Math.floor(Math.random() * root.shapePool.length)]
        color: [Colours.palette.m3primaryContainer, Colours.palette.m3secondaryContainer, Colours.palette.m3tertiaryContainer, Colours.palette.m3outlineVariant][colourIdx]
        opacity: Colours.light ? root.lightOpacities[colourIdx] : root.darkOpacities[colourIdx]
        rotation: root.rand(0, 360)

        Component.onCompleted: {
            x = root.rand(0, root.width - implicitSize);
            y = root.rand(0, root.height - implicitSize);
        }

        Behavior on color {
            CAnim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }
}
