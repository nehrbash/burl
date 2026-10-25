import "BranchGeometry.js" as Branch
import QtQuick
import qs.components
import qs.services

Canvas {
    id: root

    property bool selected: false
    property color ink: Woodland.parchmentEdge
    antialiasing: true
    onSelectedChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width, h = height;
        ctx.save();
        ctx.scale(w, h);
        for (const side of [-1, 1]) {
            const limb = [0.5, 1, 0.5 + side * 0.12, 0.80,
                0.5 + side * 0.48, 0.94, 0.5 + side * 0.44, 0.51];
            const tip = [0.5 + side * 0.44, 0.51, 0.5 + side * 0.42, 0.32,
                0.5 + side * 0.48, 0.19, 0.5 + side * 0.25, 0.06];
            Branch.gnarled(ctx, limb, 0.11, 1, side + 17,
                Woodland.barkEdge, Woodland.barkShaded, Woodland.barkLit, 1, {});
            Branch.gnarled(ctx, tip, 0.055, 1, side + 29,
                Woodland.barkEdge, Woodland.barkShaded, Woodland.barkLit, 2, {});
        }
        ctx.restore();
        ctx.lineCap = "round";
        ctx.strokeStyle = Qt.alpha(ink, selected ? 0.95 : 0.52);
        ctx.lineWidth = selected ? 1.5 : 1;
        ctx.beginPath();
        for (const side of [-1, 1]) {
            ctx.moveTo(w * (0.5 + side * 0.13), h * 0.88);
            ctx.bezierCurveTo(w * (0.5 + side * 0.39), h * 0.84,
                w * (0.5 + side * 0.44), h * 0.68,
                w * (0.5 + side * 0.44), h * 0.5);
            ctx.moveTo(w * (0.5 + side * 0.43), h * 0.42);
            ctx.lineTo(w * (0.5 + side * 0.39), h * 0.32);
        }
        ctx.stroke();
        ctx.fillStyle = selected ? ink : Woodland.brass;
        ctx.beginPath();
        ctx.moveTo(w * 0.5, h * 0.86);
        ctx.lineTo(w * 0.5 + 4, h * 0.92);
        ctx.lineTo(w * 0.5, h * 0.98);
        ctx.lineTo(w * 0.5 - 4, h * 0.92);
        ctx.closePath(); ctx.fill();
    }
}
