import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root
    title: qsTr("Mouse")

    Component.onCompleted: MouseSettings.refresh(false)

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Mouse & trackball")
        }

        ToggleRow {
            first: true
            text: qsTr("Pointer acceleration")
            subtext: qsTr("Adaptive speed for trackballs; turn off for consistent gaming movement")
            checked: MouseSettings.accelerationEnabled
            enabled: MouseSettings.ready && !MouseSettings.busy
            onToggled: {
                MouseSettings.setValue("accel_profile", checked ? "adaptive" : "flat");
                checked = Qt.binding(() => MouseSettings.accelerationEnabled);
            }
        }

        StepperRow {
            label: qsTr("Sensitivity")
            subtext: qsTr("Pointer speed")
            value: Math.round(MouseSettings.sensitivity * 100)
            from: -100
            to: 100
            stepSize: 5
            enabled: MouseSettings.ready && !MouseSettings.busy
            onMoved: value => MouseSettings.setValue("sensitivity", value / 100)
        }

        ToggleRow {
            text: qsTr("Natural scrolling")
            checked: MouseSettings.naturalScroll
            enabled: MouseSettings.ready && !MouseSettings.busy
            onToggled: {
                MouseSettings.setValue("natural_scroll", checked);
                checked = Qt.binding(() => MouseSettings.naturalScroll);
            }
        }

        ToggleRow {
            last: true
            text: qsTr("Left-handed buttons")
            subtext: qsTr("Swap the primary and secondary mouse buttons")
            checked: MouseSettings.leftHanded
            enabled: MouseSettings.ready && !MouseSettings.busy
            onToggled: {
                MouseSettings.setValue("left_handed", checked);
                checked = Qt.binding(() => MouseSettings.leftHanded);
            }
        }

        InfoRow {
            visible: MouseSettings.error.length > 0
            label: MouseSettings.error
            icon: "error"
        }

        NavRow {
            first: true
            last: true
            label: qsTr("Refresh mouse settings")
            icon: "refresh"
            enabled: !MouseSettings.busy
            onClicked: MouseSettings.refresh(false)
        }
    }
}
