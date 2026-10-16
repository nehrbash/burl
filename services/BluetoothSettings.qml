pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Burl.Config
import "BluetoothStartupPolicy.js" as Policy

Singleton {
    id: root

    readonly property var adapters: Bluetooth.adapters.values
    readonly property bool autoEnable: GlobalConfig.services.bluetoothAutoEnable
    property var seenAdapters: []

    function applyStartup(): void {
        seenAdapters = Policy.apply(adapters, seenAdapters, autoEnable);
    }

    onAdaptersChanged: Qt.callLater(root.applyStartup)
    onAutoEnableChanged: {
        seenAdapters = [];
        Qt.callLater(root.applyStartup);
    }
    Component.onCompleted: Qt.callLater(root.applyStartup)
}
