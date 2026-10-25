pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.services

Item {
    id: root

    property var sites: []
    property bool animated: true
    property real runeSize: 15
    property int chosen: -1
    property real light: 0
    readonly property bool awake: visible && animated && sites.length > 0 && Ambience.sway && !GameMode.enabled

    onAwakeChanged: {
        if (!awake) {
            waking.stop();
            light = 0;
        }
    }

    Timer {
        interval: 5000 + Math.random() * 11000
        running: root.awake
        repeat: true
        onTriggered: {
            root.chosen = Math.floor(Math.random() * root.sites.length);
            waking.restart();
            interval = 7000 + Math.random() * 13000;
        }
    }

    SequentialAnimation {
        id: waking
        NumberAnimation { target: root; property: "light"; from: 0; to: 0.7; duration: 1300; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 450 }
        NumberAnimation { target: root; property: "light"; to: 0; duration: 2300; easing.type: Easing.InOutSine }
    }

    Canvas {
        readonly property var site: root.sites[root.chosen]
        x: (site?.x ?? 0.5) * root.width - width / 2
        y: (site?.y ?? 0.5) * root.height - height / 2
        width: root.runeSize
        height: width * 1.5
        rotation: site?.angle ?? 0
        opacity: root.light
        visible: root.light > 0
        readonly property color ink: Woodland.mix(Woodland.brass, Colours.palette.m3primary, 0.35)
        onInkChanged: requestPaint()
        onSiteChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.scale(width, height);
            ctx.lineWidth = 0.07;
            ctx.lineCap = "round";
            ctx.strokeStyle = ink;
            ctx.beginPath();
            ctx.moveTo(0.5, 0.08); ctx.lineTo(0.5, 0.92);
            ctx.moveTo(0.18, 0.32); ctx.lineTo(0.5, 0.10); ctx.lineTo(0.82, 0.32);
            if (root.chosen % 2 === 0) {
                ctx.moveTo(0.2, 0.60); ctx.lineTo(0.5, 0.80); ctx.lineTo(0.8, 0.60);
            } else {
                ctx.moveTo(0.5, 0.38); ctx.lineTo(0.82, 0.55); ctx.lineTo(0.5, 0.72);
            }
            ctx.stroke();
        }
    }
}
