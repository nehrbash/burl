import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var delays: [0, 60, 120, 300, 600, 900, 1800, 3600]
    readonly property list<MenuItem> delayItems: [
        MenuItem {
            text: qsTr("Never")
        },
        MenuItem {
            text: qsTr("1 minute")
        },
        MenuItem {
            text: qsTr("2 minutes")
        },
        MenuItem {
            text: qsTr("5 minutes")
        },
        MenuItem {
            text: qsTr("10 minutes")
        },
        MenuItem {
            text: qsTr("15 minutes")
        },
        MenuItem {
            text: qsTr("30 minutes")
        },
        MenuItem {
            text: qsTr("1 hour")
        }
    ]
    readonly property list<MenuItem> sleepItems: [
        MenuItem {
            text: qsTr("Suspend")
        },
        MenuItem {
            text: qsTr("Suspend, then hibernate")
        },
        MenuItem {
            text: qsTr("Hibernate")
        }
    ]
    readonly property list<string> sleepValues: ["suspend", "suspendThenHibernate", "hibernate"]
    readonly property bool customTimeouts: (GlobalConfig.general.idle.timeouts ?? []).length > 0

    function delayItem(seconds: int): var {
        const i = delays.indexOf(seconds);
        return i < 0 ? null : delayItems[i];
    }

    function customText(seconds: int): string {
        return qsTr("%1 s").arg(seconds);
    }

    title: qsTr("Power & idle")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        InfoRow {
            visible: root.customTimeouts
            label: qsTr("Custom timeouts active")
            value: qsTr("general.idle.timeouts overrides the stages below")
        }

        SectionHeader {
            first: !root.customTimeouts
            text: qsTr("When idle")
        }

        SelectRow {
            first: true
            enabled: !root.customTimeouts
            label: qsTr("Lock screen")
            subtext: qsTr("Lock after no activity")
            menuItems: root.delayItems
            active: root.delayItem(GlobalConfig.general.idle.lockAfter)
            fallbackText: root.customText(GlobalConfig.general.idle.lockAfter)
            onSelected: item => GlobalConfig.general.idle.lockAfter = root.delays[root.delayItems.indexOf(item)]
        }

        SelectRow {
            enabled: !root.customTimeouts
            label: qsTr("Turn screen off")
            subtext: qsTr("Display sleeps; activity wakes it")
            menuItems: root.delayItems
            active: root.delayItem(GlobalConfig.general.idle.screenOffAfter)
            fallbackText: root.customText(GlobalConfig.general.idle.screenOffAfter)
            onSelected: item => GlobalConfig.general.idle.screenOffAfter = root.delays[root.delayItems.indexOf(item)]
        }

        SelectRow {
            enabled: !root.customTimeouts
            label: qsTr("Sleep")
            subtext: qsTr("Put the computer to sleep")
            menuOnTop: true
            menuItems: root.delayItems
            active: root.delayItem(GlobalConfig.general.idle.sleepAfter)
            fallbackText: root.customText(GlobalConfig.general.idle.sleepAfter)
            onSelected: item => GlobalConfig.general.idle.sleepAfter = root.delays[root.delayItems.indexOf(item)]
        }

        SelectRow {
            last: true
            enabled: !root.customTimeouts
            label: qsTr("Sleep mode")
            subtext: qsTr("What Sleep does")
            menuOnTop: true
            menuItems: root.sleepItems
            active: root.sleepItems[Math.max(0, root.sleepValues.indexOf(GlobalConfig.general.idle.sleepAction))]
            onSelected: item => GlobalConfig.general.idle.sleepAction = root.sleepValues[root.sleepItems.indexOf(item)]
        }

        SectionHeader {
            text: qsTr("Stay awake")
        }

        ToggleRow {
            first: true
            text: qsTr("While audio is playing")
            subtext: qsTr("Idle actions wait for playback to stop")
            checked: GlobalConfig.general.idle.inhibitWhenAudio
            onToggled: GlobalConfig.general.idle.inhibitWhenAudio = checked
        }

        ToggleRow {
            text: qsTr("While charging")
            subtext: qsTr("Idle actions only run on battery")
            checked: GlobalConfig.general.idle.inhibitWhenCharging
            onToggled: GlobalConfig.general.idle.inhibitWhenCharging = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Lock before sleep")
            subtext: qsTr("Lock the screen whenever the system suspends")
            checked: GlobalConfig.general.idle.lockBeforeSleep
            onToggled: GlobalConfig.general.idle.lockBeforeSleep = checked
        }
    }
}
