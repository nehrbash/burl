pragma ComponentBehavior: Bound

import QtQuick
import Burl.Config
import qs.components
import qs.services

// Visual layout canvas: each enabled monitor is a rectangle scaled to its
// logical size.  A single stationary MouseArea hit-tests and drags tiles
// (reading mouse coords off a moving item drifts), snapping edges to the other
// monitors.  Writes back each card's posX/posY (Hyprland logical pixels) and
// calls apply() on release, which kicks the pane's confirm/revert countdown.
StyledRect {
    id: root

    // The pane's cards Repeater; items are MonitorCards.
    required property var cards

    // Bump to recompute origin/fit (done off the drag path to avoid jitter).
    property int relayoutTick: 0

    readonly property real pad: Tokens.padding.large
    property real originX: 0
    property real originY: 0
    property real fit: 0.1

    // Effective logical size (resolution / scale, swapped for 90°/270°).
    function logW(c: var): real {
        const w = c.modeWidth / c.monScale;
        const h = c.modeHeight / c.monScale;
        return (c.monTransform === 1 || c.monTransform === 3) ? h : w;
    }
    function logH(c: var): real {
        const w = c.modeWidth / c.monScale;
        const h = c.modeHeight / c.monScale;
        return (c.monTransform === 1 || c.monTransform === 3) ? w : h;
    }

    function toCanvasX(lx: real): real {
        return pad + (lx - originX) * fit;
    }
    function toCanvasY(ly: real): real {
        return pad + (ly - originY) * fit;
    }

    function relayout(): void {
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity, any = false;
        for (let i = 0; i < cards.count; i++) {
            const c = cards.itemAt(i);
            if (!c || c.disabled)
                continue;
            any = true;
            minX = Math.min(minX, c.posX);
            minY = Math.min(minY, c.posY);
            maxX = Math.max(maxX, c.posX + logW(c));
            maxY = Math.max(maxY, c.posY + logH(c));
        }
        if (!any)
            return;
        const availW = width - pad * 2;
        const availH = height - pad * 2;
        const spanW = Math.max(1, maxX - minX);
        const spanH = Math.max(1, maxY - minY);
        const f = Math.min(availW / spanW, availH / spanH);
        root.fit = f > 0 ? f : 0.1;
        root.originX = minX - (availW / root.fit - spanW) / 2;
        root.originY = minY - (availH / root.fit - spanH) / 2;
    }

    // Canvas point -> index of the enabled card under it, or -1.
    function tileAt(px: real, py: real): int {
        for (let i = 0; i < cards.count; i++) {
            const c = cards.itemAt(i);
            if (!c || c.disabled)
                continue;
            const x = toCanvasX(c.posX), y = toCanvasY(c.posY);
            if (px >= x && px <= x + logW(c) * fit && py >= y && py <= y + logH(c) * fit)
                return i;
        }
        return -1;
    }

    // Snap the dragged card's left/top toward any other monitor's edges.
    function snap(idx: int, lx: real, ly: real): var {
        const c = cards.itemAt(idx);
        const w = logW(c), h = logH(c);
        const thresh = 16 / fit;
        let bx = lx, by = ly, bdx = thresh, bdy = thresh;
        for (let i = 0; i < cards.count; i++) {
            if (i === idx)
                continue;
            const o = cards.itemAt(i);
            if (!o || o.disabled)
                continue;
            const ow = logW(o), oh = logH(o);
            const oL = o.posX, oR = o.posX + ow, oT = o.posY, oB = o.posY + oh;
            for (const cand of [oL, oR, oL - w, oR - w]) {
                const d = Math.abs(cand - lx);
                if (d < bdx) {
                    bdx = d;
                    bx = cand;
                }
            }
            for (const cand of [oT, oB, oT - h, oB - h]) {
                const d = Math.abs(cand - ly);
                if (d < bdy) {
                    bdy = d;
                    by = cand;
                }
            }
        }
        return {
            x: bx,
            y: by
        };
    }

    implicitHeight: 240
    radius: Tokens.rounding.medium
    color: Colours.layer(Colours.palette.m3surfaceContainer, 1)

    // Enabling a monitor (and revert) goes through persistAndReload, which
    // replaces Monitors.all -> the pane's cards are destroyed and rebuilt with
    // fresh geometry.  Neither our size nor cards.count moves, so nothing here
    // would notice: the tiles would keep pointing at dead cards and the fit
    // would stay scaled to the old layout, leaving the new monitor off-canvas.
    function resync(): void {
        for (let i = 0; i < tiles.count; i++)
            tiles.itemAt(i)?.rebind();
        relayout();
    }

    onWidthChanged: relayout()
    onHeightChanged: relayout()
    onRelayoutTickChanged: relayout()
    Component.onCompleted: relayout()

    Connections {
        target: Monitors

        // Deferred so the pane's Repeater has rebuilt its cards first.
        function onAllChanged(): void {
            Qt.callLater(root.resync);
        }
    }

    Repeater {
        id: tiles

        model: root.cards.count
        onCountChanged: Qt.callLater(root.resync)

        Item {
            id: tile

            required property int index

            // cards.itemAt() isn't a bindable read; resync() re-fetches it.
            property var card: null

            function rebind(): void {
                card = root.cards.itemAt(index);
            }

            Component.onCompleted: rebind()

            visible: card && !card.disabled
            x: card ? root.toCanvasX(card.posX) : 0
            y: card ? root.toCanvasY(card.posY) : 0
            width: card ? root.logW(card) * root.fit : 0
            height: card ? root.logH(card) * root.fit : 0

            StyledRect {
                anchors.fill: parent
                anchors.margins: 2
                radius: Tokens.rounding.small
                color: dragArea.dragIndex === tile.index ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest
                border.width: 1
                border.color: Woodland.creamSecondary

                StyledText {
                    anchors.centerIn: parent
                    text: tile.card?.outputName ?? ""
                    font.pointSize: Tokens.font.body.small.pointSize
                    color: Colours.palette.m3onSurface
                }
            }
        }
    }

    MouseArea {
        id: dragArea

        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true

        property int dragIndex: -1
        property real pressX: 0
        property real pressY: 0
        property real startLX: 0
        property real startLY: 0

        // A bare click is not a rearrangement: without this, tapping a tile
        // re-applied the layout and armed the confirm/revert countdown.
        property bool moved: false

        onPressed: mouse => {
            dragIndex = root.tileAt(mouse.x, mouse.y);
            if (dragIndex >= 0) {
                const c = root.cards.itemAt(dragIndex);
                pressX = mouse.x;
                pressY = mouse.y;
                startLX = c.posX;
                startLY = c.posY;
                moved = false;
            }
        }
        onPositionChanged: mouse => {
            if (!pressed || dragIndex < 0) {
                cursorShape = root.tileAt(mouse.x, mouse.y) >= 0 ? Qt.SizeAllCursor : Qt.ArrowCursor;
                return;
            }
            const c = root.cards.itemAt(dragIndex);
            const lx = startLX + (mouse.x - pressX) / root.fit;
            const ly = startLY + (mouse.y - pressY) / root.fit;
            const s = root.snap(dragIndex, lx, ly);
            if (Math.round(s.x) !== c.posX || Math.round(s.y) !== c.posY)
                moved = true;
            c.posX = Math.round(s.x);
            c.posY = Math.round(s.y);
        }
        onReleased: {
            if (dragIndex >= 0 && moved) {
                root.cards.itemAt(dragIndex).apply();
                root.relayoutTick++;
            }
            dragIndex = -1;
            moved = false;
        }
    }
}
