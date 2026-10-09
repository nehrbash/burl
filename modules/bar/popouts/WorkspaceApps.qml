pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.components
import qs.components.widgets
import qs.services
import qs.utils
import Burl.Config
import "../../../components/widgets/BranchGeometry.js" as Branch

Item {
    id: root

    required property PopoutState popouts

    readonly property int branchSeed: Math.abs(popouts.workspaceId) * 47 + 13
    readonly property bool branchFlipped: branchSeed % 3 === 0
    readonly property real branchAspect: 0.32 + Branch.random(branchSeed) * 0.16
    readonly property real branchSilhouette: [-0.1, 0.1, 0][branchSeed % 3]
    readonly property real branchBend: root.branchFlipped ? root.branchSilhouette : -root.branchSilhouette
    readonly property real iconSize: Math.max(30, Tokens.sizes.bar.innerWidth * 0.9)
    readonly property real sealSize: root.iconSize + 20
    readonly property real attachmentInset: Tokens.padding.extraLargeIncreased / 2 + Tokens.padding.large
    readonly property bool awake: root.visible && root.popouts.hasCurrent && root.popouts.currentName === "workspaceapps"
    readonly property color woodDark: Woodland.mix(Woodland.barkEdge, Colours.palette.m3surface, 0.50)
    readonly property color woodMid: Woodland.mix(Woodland.barkShaded, Colours.palette.m3secondary, 0.08)
    readonly property color woodLight: Woodland.mix(Woodland.barkLit, Woodland.parchmentEdge, 0.26)
    // UV centerline and arrival values sampled from sidebar-bough-growth.png.
    readonly property var boughPath: [[0.01,0.53,0.0], [0.1,0.57,0.098], [0.2,0.57,0.2], [0.3,0.53,0.298],
        [0.4,0.59,0.4078], [0.5,0.57,0.5098], [0.6,0.61,0.6196], [0.7,0.52,0.7216],
        [0.8,0.55,0.8235], [0.9,0.49,0.9294], [0.95,0.425,0.9922]]

    function boughPoint(u: real): var {
        let before = root.boughPath[0], after = root.boughPath[root.boughPath.length - 1];
        for (let i = 1; i < root.boughPath.length; ++i) {
            after = root.boughPath[i];
            if (u <= after[0]) break;
            before = after;
        }
        const p = Math.max(0, Math.min(1, (u - before[0]) / Math.max(0.001, after[0] - before[0])));
        const sampled = before[1] + (after[1] - before[1]) * p;
        const base = root.branchFlipped ? 1 - sampled : sampled;
        const v = base + (root.branchFlipped ? 1 : -1) * root.branchBend * Math.sin(Math.PI * u);
        return { x: (paintedBough.x + u * paintedBough.width) / Math.max(1, root.width),
                 y: (paintedBough.y + v * paintedBough.height) / Math.max(1, root.height),
                 arrival: before[2] + (after[2] - before[2]) * p };
    }

    readonly property var windows: {
        const all = Hypr.toplevels.values.filter(c => c.workspace?.id === root.popouts.workspaceId);
        if (root.popouts.workspaceId < 0)
            return all;
        const active = all.find(t => t.activated) ?? all[0];
        return all.filter(t => t !== active);
    }
    readonly property var limbs: {
        const result = [];
        for (let i = 0; i < root.windows.length; ++i) {
            const seed = root.branchSeed + i * 31;
            const x = root.windows.length === 1 ? 0.45 + Branch.random(seed) * 0.16 : 0.19 + i * 0.68 / (root.windows.length - 1) + (Branch.random(seed) - 0.5) * 0.045;
            const t = Math.max(0.08, x - 0.09), p = root.boughPoint(t);
            const up = (i + root.branchSeed) % 2 === 0;
            const start = Math.min(0.72, (p.arrival + 0.038) / 1.04 * 0.72);
            const y = up ? 0.16 + Branch.random(seed + 77) * 0.07 : 0.71 + Branch.random(seed + 41) * 0.06;
            result.push({ b: [p.x, p.y, p.x + 0.10, p.y + (up ? -0.08 : 0.10),
                              x - 0.04, y + (up ? 0.12 : -0.14), x, y],
                          start: start, span: Math.min(0.38, 1 - start), seed: seed, cache: {} });
        }
        return result;
    }

    property real growth: 0
    property real sap: 0
    property int hoveredIndex: -1

    function progress(limb: var): real {
        return Math.max(0, Math.min(1, (root.growth - limb.start) / limb.span));
    }

    function grow(): void {
        growthAnimation.stop();
        root.hoveredIndex = -1;
        root.growth = 0;
        if (root.awake && Ambience.grow && !GameMode.enabled)
            growthAnimation.start();
        else
            root.growth = 1;
    }

    implicitWidth: Math.min(760, Math.max(340, 140 + root.windows.length * 86 + Branch.random(root.branchSeed + 5) * 70))
    implicitHeight: Math.max(250, root.implicitWidth * 809 / 1942 + 20)
    Component.onCompleted: root.grow()
    onWindowsChanged: if (root.awake) Qt.callLater(root.grow)
    onAwakeChanged: {
        if (root.awake)
            root.grow();
        else {
            growthAnimation.stop();
            root.hoveredIndex = -1;
        }
    }
    onGrowthChanged: bough.requestPaint()
    onHoveredIndexChanged: bough.requestPaint()
    onWoodDarkChanged: bough.requestPaint()
    onWoodMidChanged: bough.requestPaint()
    onWoodLightChanged: bough.requestPaint()

    NumberAnimation {
        id: growthAnimation
        target: root
        property: "growth"
        from: 0; to: 1
        duration: 1250
        easing.type: Easing.InOutCubic
    }

    NumberAnimation on sap {
        running: root.awake && Ambience.sway && !GameMode.enabled
        from: 0; to: 1
        duration: 4400
        loops: Animation.Infinite
    }

    Canvas {
        id: bough
        x: -root.attachmentInset
        width: root.width + root.attachmentInset
        height: root.height
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.translate(root.attachmentInset, 0);
            ctx.scale(root.width, height);
            for (let i = 0; i < root.limbs.length; ++i) {
                const limb = root.limbs[i], p = root.progress(limb);
                Branch.gnarled(ctx, limb.b, 0.014 * root.height / Math.max(1, root.width), p, limb.seed,
                    root.woodDark, root.woodMid, root.woodLight, 1, limb.cache);
                ctx.save();
                ctx.beginPath();
                ctx.lineCap = "round";
                ctx.strokeStyle = root.woodLight;
                ctx.globalAlpha = 0.48;
                ctx.lineWidth = 0.003;
                Branch.partialCurve(ctx, limb.b, p);
                ctx.stroke();
                ctx.restore();
                if (i === root.hoveredIndex) {
                    ctx.beginPath();
                    ctx.strokeStyle = Qt.alpha(Colours.palette.m3primary, 0.7);
                    ctx.lineWidth = 0.0018;
                    Branch.partialCurve(ctx, limb.b, p);
                    ctx.stroke();
                }
            }

        }
    }

    PaintedTree {
        id: paintedBough
        x: -root.attachmentInset
        width: root.width + root.attachmentInset
        height: width * root.branchAspect
        y: root.height * 0.5 - height * (root.branchFlipped ? 0.47 : 0.53)
        transform: Scale { origin.y: paintedBough.height / 2; yScale: root.branchFlipped ? -1 : 1 }
        artSource: Quickshell.shellPath("assets/images/tree/rendered/sidebar-bough.png")
        growthSource: Quickshell.shellPath("assets/images/tree/rendered/sidebar-bough-growth.png")
        goldMix: 0.06
        brightness: 1.0
        bend: root.branchBend
        growth: Math.min(1, root.growth / 0.72)
        animated: root.awake
    }

    Repeater {
        model: 10
        delegate: Rectangle {
            required property int index
            readonly property real t: (root.sap + index * 0.071) % 1
            readonly property var point: root.boughPoint(0.01 + t * 0.93)
            x: point.x * root.width - width / 2
            y: point.y * root.height - height / 2
            width: index % 3 === 0 ? 3 : 1.5
            height: width
            radius: width / 2
            color: Colours.palette.m3primary
            opacity: Math.sin(t * Math.PI) * 0.6
            visible: root.growth > 0.98 && root.awake && Ambience.sway && !GameMode.enabled
        }
    }

    Repeater {
        model: ScriptModel { values: root.windows }
        delegate: Item {
            id: slot
            required property var modelData
            required property int index
            readonly property var limb: root.limbs[index]
            readonly property real progress: limb ? root.progress(limb) : 0
            readonly property var tip: limb ? Branch.point(limb.b, progress) : { x: 0, y: 0.5 }
            readonly property string appId: modelData.lastIpcObject?.class ?? modelData.wayland?.appId ?? ""
            readonly property string label: modelData.title || appId || qsTr("Window")
            readonly property real bloom: Math.max(0, Math.min(1, (progress - 0.42) / 0.58))

            x: tip.x * root.width - width / 2
            y: tip.y * root.height - height / 2
            width: root.sealSize
            height: width
            opacity: bloom
            property real hoverBump: mouse.containsMouse ? 1.08 : 1
            scale: (0.35 + 0.65 * bloom) * hoverBump
            Behavior on hoverBump {
                enabled: Ambience.grow && !GameMode.enabled
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            visible: bloom > 0.001

            SpiritMedallion {
                anchors.fill: parent
                glyph: ""
                accent: Colours.palette.m3primary
                hovered: mouse.containsMouse
                animate: root.awake
                phase: slot.index + 1
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: root.iconSize
                source: Icons.getAppIcon(slot.appId, "application-x-executable")
                asynchronous: true
            }

            Rectangle {
                id: labelPlate
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: 4
                width: Math.min(136, title.implicitWidth + 18)
                height: 24
                radius: height / 2
                color: Colours.palette.m3surfaceContainer
                border.width: 1
                border.color: Qt.alpha(mouse.containsMouse ? Colours.palette.m3primary : Colours.palette.m3outline, 0.22)
                Text {
                    id: title
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: slot.label
                    textFormat: Text.PlainText
                    color: Colours.palette.m3onSurface
                    font.pixelSize: 11
                }
            }

            MouseArea {
                id: mouse
                x: Math.min(-6, labelPlate.x)
                y: -6
                width: Math.max(slot.width + 12, labelPlate.width)
                height: slot.height + labelPlate.height + 16
                hoverEnabled: true
                enabled: slot.progress > 0.9
                cursorShape: Qt.PointingHandCursor
                onEntered: root.hoveredIndex = slot.index
                onExited: if (root.hoveredIndex === slot.index) root.hoveredIndex = -1
                onClicked: {
                    const addr = slot.modelData.address;
                    Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "address:0x${addr}" })` : `focuswindow address:0x${addr}`);
                    root.popouts.hasCurrent = false;
                }
            }
        }
    }
}
