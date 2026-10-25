import QtQuick
import qs.components

Canvas {
    id: root

    property real rootX: width / 2
    property real rootY: height * 0.94
    property real rootSpan: width * 0.6
    readonly property color soil: Woodland.mix(Woodland.barkEdge, "#16151d", 0.88)
    antialiasing: true
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onRootXChanged: requestPaint()
    onRootYChanged: requestPaint()
    onRootSpanChanged: requestPaint()
    onSoilChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const horizon = rootY - height * 0.19;
        ctx.beginPath();
        ctx.moveTo(0, horizon + height * 0.035);
        ctx.bezierCurveTo(width * 0.18, horizon - height * 0.018,
            rootX - rootSpan * 0.3, horizon + height * 0.035, rootX, horizon);
        ctx.bezierCurveTo(rootX + rootSpan * 0.3, horizon - height * 0.015,
            width * 0.85, horizon + height * 0.025, width, horizon + height * 0.01);
        ctx.lineTo(width, height); ctx.lineTo(0, height); ctx.closePath();
        const earth = ctx.createLinearGradient(0, horizon, 0, height);
        earth.addColorStop(0, "transparent");
        earth.addColorStop(0.18, Qt.alpha(soil, 0.5));
        earth.addColorStop(0.45, soil);
        earth.addColorStop(1, "#100e13");
        ctx.fillStyle = earth;
        ctx.fill();
        ctx.save();
        ctx.clip();
        ctx.lineWidth = 1;
        for (let i = 0; i < 26; ++i) {
            const depth = ((i * 37 + 11) % 97) / 97;
            const x = ((i * 131 + 29) % 997) / 997 * width;
            const y = horizon + (height - horizon) * depth;
            const span = width * (0.015 + depth * 0.055);
            ctx.strokeStyle = Qt.alpha(Woodland.parchmentEdge, 0.025 + depth * 0.035);
            ctx.beginPath();
            ctx.moveTo(x - span, y);
            ctx.quadraticCurveTo(x, y - 2 - depth * 3, x + span, y + depth * 2);
            ctx.stroke();
        }
        for (let i = 0; i < 180; ++i) {
            const depth = ((i * 41 + 17) % 173) / 173;
            const x = ((i * 227 + 31) % 997) / 997 * width;
            const y = horizon + (height - horizon) * depth;
            ctx.fillStyle = Qt.alpha(Woodland.parchmentEdge, depth * 0.05);
            ctx.fillRect(x, y, 1 + depth * 3, 0.5 + depth);
        }
        ctx.restore();
        ctx.save();
        ctx.translate(rootX, rootY);
        ctx.scale(rootSpan * 0.6, height * 0.065);
        const contact = ctx.createRadialGradient(0, 0, 0, 0, 0, 1);
        contact.addColorStop(0, "#e609080b");
        contact.addColorStop(0.5, "#a609080b");
        contact.addColorStop(1, "transparent");
        ctx.fillStyle = contact;
        ctx.fillRect(-1, -1, 2, 2);
        ctx.restore();
    }
}
