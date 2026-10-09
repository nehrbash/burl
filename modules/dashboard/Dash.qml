pragma ComponentBehavior: Bound

import "dash"
import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.filedialog

GridLayout {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker
    // Living-tree mode: no solid panel sits behind this grid any more, so the
    // gaps between cards have to be wide enough to show wallpaper, and every
    // card's own fill has to stop tracking the shell's transparency setting
    // (BarkCard.opaque).
    property bool living: false
    readonly property bool folio: userPlate.folio

    // SCATTER — living mode only. The grid still does all the placement
    // (columns/rows/spacing below are untouched), this only perturbs the
    // PAINT: a small per-card translate + rotation so cards read as hanging
    // off a branch instead of ruled into a table. Deterministic, same idiom
    // BarkCard.grainSeed/_grainHash already uses (see BarkCard.qml) — a Knuth
    // multiplicative hash of the card's own seed, so the scatter is identical
    // every reload/rebind and never reshuffles like Math.random() would.
    // Reseeded with +37 (BarkCard reseeds grain with +1) so a card's scatter
    // and its grain phase are independent draws off the same seed.
    function _scatterHash(seed: int): real {
        return Math.floor(((seed + 37) * 2654435761) % 4294967296);
    }

    // ±12px. Cards only ever carry `columnSpacing`/`rowSpacing` (extraLarge in
    // living mode) worth of empty gutter around them, so this — plus the
    // rotation bulge below — has to stay well inside that gutter or a card's
    // rotated corner pokes into its neighbour. Worst-case combined escape
    // (biggest card, Media, ~200x300) is ~18px; extraLarge spacing clears it.
    function scatterX(seed: int): real {
        return root.living && !root.folio ? (root._scatterHash(seed) % 25) - 12 : 0;
    }

    // ±10px, independent draw from the same hash (next digits after scatterX
    // consumes the low ones).
    function scatterY(seed: int): real {
        return root.living && !root.folio ? (Math.floor(root._scatterHash(seed) / 25) % 21) - 10 : 0;
    }

    // ±2.4° max. Kept to "a few degrees" on purpose: these are readable
    // widgets (clock digits, calendar grid, weather text), not scrapbook
    // photos — anything past ~3° starts reading as crooked rather than
    // organic. At 2.4° the rotation is whole-card (BarkCard's `rotation`
    // rotates the card and everything inside it rigidly about its own
    // centre), so glyphs stay undistorted relative to each other; only the
    // card's edge against the wallpaper tilts.
    function scatterRot(seed: int): real {
        return root.living && !root.folio ? (Math.floor(root._scatterHash(seed) / 525) % 49) / 10 - 2.4 : 0;
    }

    // ±6px, a third independent draw. Applied only to the two cards that
    // already carry a real content-driven Layout.preferredHeight (weather,
    // calendar below) so their row height stops being an exact multiple of
    // the fillHeight cards' stretch target — a small, safe nudge rather than
    // a rework of every dash/* card's internal (anchors.fill-based) sizing.
    function scatterH(seed: int): real {
        return root.living && !root.folio ? (Math.floor(root._scatterHash(seed) / 525 / 49) % 13) - 6 : 0;
    }

    rowSpacing: root.living && !root.folio ? Tokens.spacing.extraLarge : Tokens.spacing.medium
    columnSpacing: root.living && !root.folio ? Tokens.spacing.extraLarge : Tokens.spacing.medium

    Rect {
        id: userPlate
        Layout.column: 2
        Layout.columnSpan: 3
        Layout.preferredWidth: Tokens.sizes.dashboard.userWidth
        Layout.fillHeight: true

        radius: Tokens.rounding.extraLarge
        // The one moss card on this tab — it is the hero, everything else stays quiet.
        moss: true
        grainSeed: 1
        opaque: root.living
        rotation: root.scatterRot(1)
        transform: Translate {
            x: root.scatterX(1)
            y: root.scatterY(1)
        }

        User {
            id: user

            screenState: root.screenState
            facePicker: root.facePicker
        }
    }

    Rect {
        Layout.row: 0
        Layout.columnSpan: 2
        Layout.preferredWidth: Tokens.sizes.dashboard.weatherWidth
        Layout.preferredHeight: weather.implicitHeight + root.scatterH(2)

        radius: Tokens.rounding.extraLarge * 1.5
        grainSeed: 2
        // 275 x ~95: nearly 3:1, so the fissures run along the card, not across it.
        grainHorizontal: true
        opaque: root.living
        rotation: root.scatterRot(2)
        transform: Translate {
            x: root.scatterX(2)
            y: root.scatterY(2)
        }

        SmallWeather {
            id: weather
        }
    }

    Rect {
        Layout.row: 1
        Layout.preferredWidth: dateTime.implicitWidth
        Layout.fillHeight: true

        radius: Tokens.rounding.large
        grainSeed: 3
        opaque: root.living
        rotation: root.scatterRot(3)
        transform: Translate {
            x: root.scatterX(3)
            y: root.scatterY(3)
        }

        DateTime {
            id: dateTime
        }
    }

    Rect {
        Layout.row: 1
        Layout.column: 1
        Layout.columnSpan: 3
        Layout.fillWidth: true
        Layout.preferredHeight: calendar.implicitHeight + root.scatterH(4)

        radius: Tokens.rounding.extraLarge
        grainSeed: 4
        opaque: root.living
        rotation: root.scatterRot(4)
        transform: Translate {
            x: root.scatterX(4)
            y: root.scatterY(4)
        }

        Calendar {
            id: calendar

            screenState: root.screenState
        }
    }

    Rect {
        Layout.row: 1
        Layout.column: 4
        Layout.preferredWidth: resources.implicitWidth
        Layout.fillHeight: true

        radius: Tokens.rounding.large
        grainSeed: 5
        opaque: root.living
        rotation: root.scatterRot(5)
        transform: Translate {
            x: root.scatterX(5)
            y: root.scatterY(5)
        }

        Resources {
            id: resources
        }
    }

    Rect {
        Layout.row: 0
        Layout.column: 5
        Layout.rowSpan: 2
        Layout.preferredWidth: media.implicitWidth
        Layout.fillHeight: true

        radius: Tokens.rounding.extraLarge * 2
        // No hem on this card: at r=56 corners and this size a legible hem
        // would read as a glued-on green band.
        grainSeed: 6
        opaque: root.living
        rotation: root.scatterRot(6)
        transform: Translate {
            x: root.scatterX(6)
            y: root.scatterY(6)
        }

        Media {
            id: media
        }
    }

    // Bark skin, carved rim and (opt-in) edge crust all live in BarkCard.
    component Rect: BarkCard {}
}
