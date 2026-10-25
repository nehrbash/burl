import QtQuick
import qs.components
import qs.services

Canvas {
    id: root

    property bool selected: false
    property color ink: Woodland.mix(Woodland.parchmentEdge, Colours.palette.m3primary, 0.35)
    antialiasing: true
    onSelectedChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.strokeStyle = Qt.alpha(ink, selected ? 0.9 : 0.48);
        ctx.lineWidth = 1;
        const cx = width / 2;
        ctx.beginPath();
        for (const side of [-1, 1]) {
            const y = side < 0 ? 3 : height - 3;
            ctx.moveTo(cx - 10, y - side * 2);
            ctx.quadraticCurveTo(cx - 5, y + side * 4, cx, y);
            ctx.quadraticCurveTo(cx + 5, y + side * 4, cx + 10, y - side * 2);
            ctx.moveTo(cx, y - 3); ctx.lineTo(cx + 3, y);
            ctx.lineTo(cx, y + 3); ctx.lineTo(cx - 3, y); ctx.closePath();
        }
        const length = Math.min(9, height * 0.18);
        for (const x of [2, width - 2]) {
            const direction = x < cx ? 1 : -1;
            for (const y of [7, height - 7]) {
                const down = y < height / 2 ? 1 : -1;
                ctx.moveTo(x + direction * 5, y);
                ctx.lineTo(x, y); ctx.lineTo(x, y + down * length);
            }
        }
        ctx.stroke();
        if (selected) {
            ctx.fillStyle = ink;
            for (const x of [2, width - 2]) {
                const y = height / 2;
                ctx.beginPath();
                ctx.moveTo(x, y - 4); ctx.lineTo(x + 2, y);
                ctx.lineTo(x, y + 4); ctx.lineTo(x - 2, y);
                ctx.closePath(); ctx.fill();
            }
        }
    }
}
