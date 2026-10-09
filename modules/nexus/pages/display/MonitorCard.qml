pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

SectionContainer {
    id: root

    // Raw `hyprctl monitors all -j` object this card edits (may be disabled).
    required property var monitor

    // Emitted after any live (eval-applied) change, so the pane can start its
    // confirm/revert countdown.
    signal edited()

    // Emitted when this monitor's footprint on the arrangement canvas changes
    // (its size on screen, or whether it is shown at all).  posX/posY are left
    // out on purpose: the canvas writes those itself while dragging and refits
    // on release.
    signal previewChanged()

    // Emitted when the user toggles a disabled monitor back ON.  eval can't
    // re-enable an output, so the pane handles this via persist + reload.
    signal enableRequested()

    // Editable state, seeded from the live monitor on load.
    property bool disabled: false
    property int modeWidth: 0
    property int modeHeight: 0
    property real modeRefresh: 60
    property int posX: 0
    property int posY: 0
    property real monScale: 1
    property int monTransform: 0
    property bool vrr: false
    property bool tenBit: false

    // Parsed availableModes: [{ label, width, height, refresh }]
    property var modes: []

    // The last config actually pushed to the compositor.  Every control here
    // only stages an edit — nothing touches the hardware until Apply — so this
    // is what "unchanged" means.
    property var applied: null

    readonly property bool dirty: !!applied && JSON.stringify(config()) !== JSON.stringify(applied)

    readonly property string outputName: monitor?.name ?? ""

    // Stable desc:-based identity used for live-apply + persistence (set on load).
    property string descKey: ""

    // Build a config object for Monitors.applyLive / .persist.
    function config(): var {
        return {
            output: root.descKey,
            disabled: root.disabled,
            width: root.modeWidth,
            height: root.modeHeight,
            refresh: root.modeRefresh,
            x: root.posX,
            y: root.posY,
            scale: root.monScale,
            transform: root.monTransform,
            vrr: root.vrr ? 1 : 0,
            bitdepth: root.tenBit ? 10 : 8
        };
    }

    function apply(): void {
        root.applied = root.config();
        Monitors.applyLive(root.applied);
        root.edited();
    }

    // Drop staged edits and go back to what is on screen.
    function reset(): void {
        if (root.applied)
            root.load(root.applied);
    }

    // Restore editable state from a config object (used by the pane on revert).
    // These are plain property writes, so they don't re-fire apply().
    function load(cfg: var): void {
        root.disabled = cfg.disabled ?? false;
        root.modeWidth = cfg.width;
        root.modeHeight = cfg.height;
        root.modeRefresh = cfg.refresh;
        root.posX = cfg.x;
        root.posY = cfg.y;
        root.monScale = cfg.scale;
        root.monTransform = cfg.transform;
        root.vrr = cfg.vrr === 1 || cfg.vrr === true;
        root.tenBit = cfg.bitdepth === 10;
        root.applied = root.config();
    }

    // Hyprland only accepts a scale that makes the logical size a whole number
    // of pixels; given anything else it silently hunts for the nearest valid
    // scale in 1/120 steps.  Quantise here so the field, the preview and the
    // hardware agree on what was applied.
    function _validScale(s: real): real {
        const w = root.modeWidth;
        const h = root.modeHeight;
        const fallback = Math.round(s * 100) / 100;
        if (!(w > 0) || !(h > 0))
            return fallback;
        const whole = v => Math.abs(v - Math.round(v)) < 1e-6;
        const base = Math.round(s * 120);
        for (let d = 0; d < 90; d++) {
            for (const cand of d === 0 ? [base] : [base - d, base + d]) {
                const c = cand / 120;
                if (c >= 0.5 && c <= 3 && whole(w / c) && whole(h / c))
                    return c;
            }
        }
        return fallback;
    }

    function _modeLabel(w, h, r): string {
        return `${w}×${h}  ${Math.round(r)}Hz`;
    }

    Component.onCompleted: {
        const snap = Monitors.snapshot(monitor);
        root.descKey = snap.output;
        root.disabled = snap.disabled;
        root.posX = snap.x;
        root.posY = snap.y;
        root.monScale = snap.scale;
        root.monTransform = snap.transform;
        root.vrr = snap.vrr === 1;
        root.tenBit = snap.bitdepth === 10;

        const parsed = [];
        for (const m of snap.availableModes) {
            const mm = m.match(/(\d+)x(\d+)@([\d.]+)/);
            if (mm)
                parsed.push({
                    label: root._modeLabel(+mm[1], +mm[2], +mm[3]),
                    width: +mm[1],
                    height: +mm[2],
                    refresh: +mm[3]
                });
        }
        // Ensure the current mode is selectable even if not advertised.  A
        // disabled output has no current mode (hyprctl reports 0x0@0), so skip
        // this — otherwise a bogus 0x0 entry wins the match below and gets
        // persisted as `mode = "0x0@0"`, which Hyprland rejects, and the
        // monitor never comes back.
        if (snap.width > 0 && snap.height > 0 && !parsed.some(p => p.width === snap.width && p.height === snap.height && Math.abs(p.refresh - snap.refresh) < 1))
            parsed.unshift({
                label: root._modeLabel(snap.width, snap.height, snap.refresh),
                width: snap.width,
                height: snap.height,
                refresh: snap.refresh
            });
        root.modes = parsed;

        let best = parsed[0];
        let bestD = Infinity;
        for (const p of parsed) {
            if (p.width === snap.width && p.height === snap.height) {
                const d = Math.abs(p.refresh - snap.refresh);
                if (d < bestD) {
                    bestD = d;
                    best = p;
                }
            }
        }
        if (best) {
            root.modeWidth = best.width;
            root.modeHeight = best.height;
            root.modeRefresh = best.refresh;
        }

        // Whatever we just read off the compositor is, by definition, applied.
        root.applied = root.config();
    }

    alignTop: true
    contentSpacing: Tokens.spacing.small

    onDisabledChanged: previewChanged()
    onModeWidthChanged: previewChanged()
    onModeHeightChanged: previewChanged()
    onMonScaleChanged: previewChanged()
    onMonTransformChanged: previewChanged()

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: root.outputName
                font.pointSize: Tokens.font.body.medium.pointSize
                font.weight: 500
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.monitor?.description ?? ""
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.body.small.pointSize
                elide: Text.ElideRight
            }
        }

        // Staged edits need somewhere to go; the switch stays immediate, since
        // turning a monitor off (or back on) isn't something you stage.
        HeaderButton {
            visible: root.dirty && !root.disabled
            text: qsTr("Reset")
            onClicked: root.reset()
        }

        HeaderButton {
            visible: root.dirty && !root.disabled
            text: qsTr("Apply")
            accent: true
            onClicked: root.apply()
        }

        StyledSwitch {
            checked: !root.disabled
            onToggled: {
                root.disabled = !checked;
                if (checked)
                    root.enableRequested();
                else
                    root.apply();
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        opacity: root.disabled ? 0.4 : 1
        enabled: !root.disabled

        Behavior on opacity {
            Anim {}
        }

        SelectRow {
            label: qsTr("Resolution")
            model: root.modes
            currentLabel: root._modeLabel(root.modeWidth, root.modeHeight, root.modeRefresh)
            onSelected: i => {
                const m = root.modes[i];
                root.modeWidth = m.width;
                root.modeHeight = m.height;
                root.modeRefresh = m.refresh;
            }
        }

        SectionContainer {
            contentSpacing: Tokens.spacing.medium

            SliderInput {
                Layout.fillWidth: true

                label: qsTr("Scale")
                value: root.monScale
                from: 0.5
                to: 3.0
                decimals: 3
                suffix: "×"
                validator: DoubleValidator {
                    bottom: 0.5
                    top: 3.0
                }

                // Drag and type both only stage: the preview follows, the
                // monitor waits for Apply.
                onValueModified: v => root.monScale = root._validScale(v)
                onValueCommitted: v => root.monScale = root._validScale(v)
            }
        }

        SelectRow {
            label: qsTr("Transform")
            model: [
                {
                    label: qsTr("Normal")
                },
                {
                    label: qsTr("90°")
                },
                {
                    label: qsTr("180°")
                },
                {
                    label: qsTr("270°")
                }
            ]
            currentLabel: [qsTr("Normal"), qsTr("90°"), qsTr("180°"), qsTr("270°")][root.monTransform] ?? qsTr("Normal")
            onSelected: i => {
                root.monTransform = i;
            }
        }

        SwitchRow {
            label: qsTr("Variable refresh rate")
            checked: root.vrr
            onToggled: checked => {
                root.vrr = checked;
            }
        }

        SwitchRow {
            label: qsTr("10-bit colour")
            checked: root.tenBit
            onToggled: checked => {
                root.tenBit = checked;
            }
        }
    }

    component HeaderButton: StyledRect {
        id: hdrBtn

        property string text
        property bool accent: false

        signal clicked

        implicitWidth: hdrText.implicitWidth + Tokens.padding.large * 2
        implicitHeight: hdrText.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.small
        color: accent ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

        StateLayer {
            onClicked: hdrBtn.clicked()
        }

        StyledText {
            id: hdrText

            anchors.centerIn: parent
            text: hdrBtn.text
            color: hdrBtn.accent ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
        }
    }

    component SelectRow: StyledRect {
        id: sel

        property string label
        property var model: []
        property string currentLabel: ""

        signal selected(int index)

        Layout.fillWidth: true
        implicitHeight: selInner.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.medium
        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

        RowLayout {
            id: selInner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledText {
                Layout.fillWidth: true
                text: sel.label
            }

            StyledRect {
                implicitWidth: valueRow.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: valueRow.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.small
                color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

                RowLayout {
                    id: valueRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: sel.currentLabel
                    }

                    MaterialIcon {
                        text: "expand_more"
                        font.pointSize: Tokens.font.body.medium.pointSize
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popup.open()
                }

                Popup {
                    id: popup

                    y: parent.height + Tokens.spacing.small
                    width: Math.max(parent.width, 160)
                    implicitHeight: Math.min(contentHeight, 280)
                    padding: Tokens.padding.small
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                    background: StyledRect {
                        color: Colours.palette.m3surfaceContainerHighest
                        radius: Tokens.rounding.small
                    }

                    contentItem: StyledListView {
                        implicitHeight: contentHeight
                        clip: true
                        model: sel.model

                        delegate: StyledRect {
                            id: item

                            required property int index
                            required property var modelData

                            width: ListView.view.width
                            implicitHeight: itemText.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.small
                            color: "transparent"

                            StateLayer {
                                onClicked: {
                                    sel.selected(item.index);
                                    popup.close();
                                }
                            }

                            StyledText {
                                id: itemText

                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Tokens.padding.medium
                                text: item.modelData.label
                            }
                        }
                    }
                }
            }
        }
    }
}
