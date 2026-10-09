pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Burl.Config
import Burl.Services
import qs.components
import qs.components.containers
import qs.services

StyledRect {
    id: root
    implicitHeight: 72
    radius: 12
    color: Woodland.velvet

    ServiceRef { service: Cpu }
    ServiceRef { service: Memory }
    ServiceRef { service: Storage }
    WoodPanel { anchors.fill: parent }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        Repeater {
            model: [
                { label: "CPU " + Math.ceil(GlobalConfig.services.useFahrenheitPerformance ? Cpu.temperature * 1.8 + 32 : Cpu.temperature) + "°", value: Math.round(Cpu.percentage * 100) },
                { label: "RAM", value: Math.round(Memory.percentage * 100) },
                { label: "DISK", value: Math.round(Storage.percentage * 100) }
            ]
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: parent.modelData.label
                    color: Woodland.brass
                    font.pixelSize: 10
                    font.letterSpacing: 1.5
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: parent.modelData.value + "%"
                    color: Woodland.ivory
                    font.pixelSize: 20
                    font.family: "serif"
                }
            }
        }
    }
}
