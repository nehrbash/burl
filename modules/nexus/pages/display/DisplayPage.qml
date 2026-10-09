pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.nexus

Item {
    id: root

    property NexusState nState

    // Confirm/revert safety: changes apply live immediately, but auto-revert
    // after `remaining` seconds unless the user keeps them.  `committed` is the
    // last-known-good config set we revert to.
    property bool pending: false
    property int remaining: 15
    property var committed: []

    // Baseline configs straight from the live `monitors all -j` snapshot.
    function computeBaseline(): var {
        return Monitors.all.map(o => {
            const s = Monitors.snapshot(o);
            return {
                output: s.output,
                disabled: s.disabled,
                width: s.width,
                height: s.height,
                refresh: s.refresh,
                x: s.x,
                y: s.y,
                scale: s.scale,
                transform: s.transform,
                vrr: s.vrr,
                bitdepth: s.bitdepth
            };
        });
    }

    function gatherConfigs(): var {
        const configs = [];
        for (let i = 0; i < cardsRepeater.count; i++) {
            const c = cardsRepeater.itemAt(i);
            if (c)
                configs.push(c.config());
        }
        return configs;
    }

    function startCountdown(): void {
        root.remaining = 15;
        root.pending = true;
        countdown.restart();
    }

    function keep(): void {
        countdown.stop();
        const configs = root.gatherConfigs();
        // Changes were already eval-applied live; just write them to disk.
        Monitors.persist(configs);
        root.committed = configs;
        root.pending = false;
    }

    function revert(): void {
        countdown.stop();
        // Sync the card UI back to the committed state...
        for (let i = 0; i < cardsRepeater.count; i++) {
            const c = cardsRepeater.itemAt(i);
            if (!c)
                continue;
            const cfg = root.committed.find(x => x.output === c.descKey);
            if (cfg)
                c.load(cfg);
        }
        // ...then reload, which restores it for real (and re-enables any output
        // an eval-disable can't bring back).  generated.lua == committed here.
        Monitors.persistAndReload(root.committed);
        root.pending = false;
    }

    // Toggling a monitor on can't be done with a live eval, so persist the new
    // (enabled) layout and reload.  Enabling is safe, so we commit immediately
    // rather than arming the revert countdown.
    // A monitor that was off has no live position (hyprctl reports 0x0), so a
    // freshly enabled one would be persisted stacked on top of another and the
    // arrangement canvas would show one tile hiding the other.  Park each
    // newly-enabled output to the right of everything already placed.
    function placeNewlyEnabled(): void {
        let right = 0;
        for (let i = 0; i < cardsRepeater.count; i++) {
            const c = cardsRepeater.itemAt(i);
            if (!c || c.disabled || (c.monitor?.disabled ?? false))
                continue;
            right = Math.max(right, c.posX + arrangement.logW(c));
        }
        for (let i = 0; i < cardsRepeater.count; i++) {
            const c = cardsRepeater.itemAt(i);
            if (!c || c.disabled || !(c.monitor?.disabled ?? false))
                continue;
            c.posX = Math.round(right);
            c.posY = 0;
            right += arrangement.logW(c);
        }
    }

    function enableMonitors(): void {
        countdown.stop();
        root.placeNewlyEnabled();
        const configs = root.gatherConfigs();
        Monitors.persistAndReload(configs);
        root.committed = configs;
        root.pending = false;
    }

    anchors.fill: parent

    onVisibleChanged: if (visible && !pending)
        Monitors.refresh()
    Component.onCompleted: Monitors.refresh()

    Connections {
        target: Monitors

        function onAllChanged(): void {
            if (!root.pending)
                root.committed = root.computeBaseline();
        }
    }

    Timer {
        id: countdown

        interval: 1000
        repeat: true
        onTriggered: {
            root.remaining -= 1;
            if (root.remaining <= 0)
                root.revert();
        }
    }

    StyledFlickable {
        id: flickable

        anchors.fill: parent
        anchors.margins: Tokens.padding.large

        flickableDirection: Flickable.VerticalFlick
        contentHeight: layout.height

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: flickable
        }

        ColumnLayout {
            id: layout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Tokens.spacing.medium

            StyledText {
                text: qsTr("Monitors")
                font.pointSize: Tokens.font.body.large.pointSize
                font.weight: 500
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Drag monitors to arrange them. Other changes are staged until you hit Apply, then revert after 15s unless you keep them.")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.body.small.pointSize
                wrapMode: Text.WordWrap
            }

            MonitorArrangement {
                id: arrangement

                Layout.fillWidth: true
                cards: cardsRepeater
            }

            StyledRect {
                Layout.fillWidth: true
                visible: root.pending
                implicitHeight: bannerRow.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.medium
                color: Colours.palette.m3secondaryContainer

                RowLayout {
                    id: bannerRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Keep these display changes? Reverting in %1s").arg(root.remaining)
                        color: Colours.palette.m3onSecondaryContainer
                        wrapMode: Text.WordWrap
                    }

                    BannerButton {
                        text: qsTr("Revert")
                        onClicked: root.revert()
                    }

                    BannerButton {
                        text: qsTr("Keep")
                        accent: true
                        btnEnabled: !Monitors.persisting
                        onClicked: root.keep()
                    }
                }
            }

            Repeater {
                id: cardsRepeater

                model: Monitors.all

                MonitorCard {
                    required property var modelData

                    Layout.fillWidth: true
                    monitor: modelData
                    // The canvas can't see a card's geometry change on its
                    // own, so refit whenever one reports a new footprint.
                    // Guarded: a card can outlive the page during teardown, and
                    // an unguarded call there throws on a null page.
                    onPreviewChanged: if (arrangement)
                        arrangement.relayoutTick++
                    onEdited: if (root)
                        root.startCountdown()
                    onEnableRequested: if (root)
                        root.enableMonitors()
                }
            }
        }
    }

    component BannerButton: StyledRect {
        id: btn

        property string text
        property bool accent: false
        property bool btnEnabled: true

        signal clicked

        implicitWidth: btnText.implicitWidth + Tokens.padding.large * 2
        implicitHeight: btnText.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.small
        color: accent ? Colours.palette.m3primary : "transparent"
        opacity: btnEnabled ? 1 : 0.5

        StateLayer {
            disabled: !btn.btnEnabled
            onClicked: btn.clicked()
        }

        StyledText {
            id: btnText

            anchors.centerIn: parent
            text: btn.text
            color: btn.accent ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
        }
    }
}
