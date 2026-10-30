import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root
    title: qsTr("Hyprland")

    readonly property var effectChoices: [
        { key: "animations", label: qsTr("Disable window animations") },
        { key: "gaps", label: qsTr("Remove window gaps") },
        { key: "rounding", label: qsTr("Use square window corners") },
        { key: "opacity", label: qsTr("Make windows fully opaque") },
        { key: "shadows", label: qsTr("Disable window shadows") },
        { key: "blur", label: qsTr("Disable blur") },
        { key: "borders", label: qsTr("Use one-pixel window borders") },
        { key: "tearing", label: qsTr("Allow tearing"), detail: qsTr("For eligible fullscreen windows") },
        { key: "pauseAnimations", label: qsTr("Pause Burl animations") },
        { key: "releaseScenes", label: qsTr("Release closed Burl scenes"), detail: qsTr("Reduces memory use; reopening may take longer") },
        { key: "stopLlama", label: qsTr("Stop the local AI server"), detail: qsTr("Restarts it on exit only if performance mode stopped it") }
    ]

    function setEffect(key: string, value: bool): void {
        const next = Object.assign({}, GlobalConfig.performance);
        next[key] = value;
        GlobalConfig.performance = next;
    }

    Component.onCompleted: HyprlandPlugins.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Installed plugins")
        }

        Repeater {
            model: HyprlandPlugins.plugins
            delegate: ColumnLayout {
                id: pluginRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                ToggleRow {
                    first: true
                    text: pluginRow.modelData.name
                    subtext: pluginRow.modelData.paused ? qsTr("Paused by performance mode")
                        : pluginRow.modelData.loaded ? qsTr("Loaded") : qsTr("Not loaded")
                    checked: pluginRow.modelData.enabled
                    enabled: HyprlandPlugins.ready && !HyprlandPlugins.busy
                    onToggled: {
                        HyprlandPlugins.setChoice(pluginRow.modelData, "enabled", checked);
                        checked = Qt.binding(() => pluginRow.modelData.enabled);
                    }
                }

                ToggleRow {
                    last: true
                    text: qsTr("Disable in performance mode")
                    checked: pluginRow.modelData.disableInPerformance
                    enabled: HyprlandPlugins.ready && !HyprlandPlugins.busy
                    onToggled: {
                        HyprlandPlugins.setChoice(pluginRow.modelData, "disableInPerformance", checked);
                        checked = Qt.binding(() => pluginRow.modelData.disableInPerformance);
                    }
                }
            }
        }

        InfoRow {
            visible: HyprlandPlugins.error.length > 0
            label: HyprlandPlugins.error
            icon: "error"
        }

        NavRow {
            first: true
            last: true
            label: qsTr("Refresh plugins")
            icon: "refresh"
            enabled: !HyprlandPlugins.busy
            onClicked: HyprlandPlugins.refresh()
        }

        SectionHeader { text: qsTr("Performance mode") }

        InfoRow {
            label: qsTr("These choices apply while the system power profile is Performance.")
            icon: "speed"
        }

        Repeater {
            model: root.effectChoices
            delegate: ToggleRow {
                id: effectRow
                required property var modelData
                required property int index
                first: index === 0
                last: index === root.effectChoices.length - 1
                text: modelData.label
                subtext: modelData.detail || ""
                checked: GlobalConfig.performance[modelData.key] !== false
                enabled: modelData.key !== "stopLlama" || GameMode.llamaAvailable
                onToggled: {
                    root.setEffect(modelData.key, checked);
                    checked = Qt.binding(() => GlobalConfig.performance[effectRow.modelData.key] !== false);
                }
            }
        }
    }
}
