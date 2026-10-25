import QtQuick
import qs.services

Canvas {
    id: root

    property bool selected: false
    property color ink: Colours.palette.m3primary

    implicitHeight: 16
    opacity: selected ? 1 : 0.25
    onSelectedChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const c = getContext("2d");
        c.reset();
        c.strokeStyle = ink;
        c.lineWidth = 1;
        const mid = width / 2;
        const y = height / 2;
        c.globalAlpha = selected ? 0.85 : 1;
        c.beginPath();
        c.moveTo(4, y); c.lineTo(mid - 9, y);
        c.moveTo(mid + 9, y); c.lineTo(width - 4, y);
        c.stroke();
        if (!selected) return;
        c.beginPath();
        c.moveTo(mid, y - 5); c.lineTo(mid + 5, y);
        c.lineTo(mid, y + 5); c.lineTo(mid - 5, y); c.closePath();
        c.moveTo(mid, y - 7); c.lineTo(mid, y + 7);
        c.stroke();
        for (const side of [-1, 1]) {
            c.beginPath();
            c.moveTo(mid + side * 9, y);
            c.bezierCurveTo(mid + side * 15, y - 7, mid + side * 25, y - 6, mid + side * 23, y - 1);
            c.bezierCurveTo(mid + side * 21, y + 2, mid + side * 18, y - 1, mid + side * 21, y - 2);
            c.moveTo(mid + side * 12, y + 3);
            c.quadraticCurveTo(mid + side * 27, y + 8, mid + side * 34, y);
            c.stroke();
        }
        c.beginPath();
        c.moveTo(3, y - 2); c.lineTo(5, y); c.lineTo(3, y + 2);
        c.moveTo(width - 3, y - 2); c.lineTo(width - 5, y); c.lineTo(width - 3, y + 2);
        c.stroke();
    }
}
