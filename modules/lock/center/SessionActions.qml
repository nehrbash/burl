pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Burl.Config
import Burl.Services
import qs.components
import qs.components.controls
import qs.services

RowLayout {
    id: root

    spacing: Tokens.spacing.small

    // The configured helper selects the next boot target; logind handles rebooting.
    Process {
        id: bootToWindows

        command: Config.session.commands.windows
        onExited: code => {
            if (code === 0)
                SessionManager.reboot();
            else
                root.failed = true;
        }
    }

    property bool failed

    Action {
        icon: Config.session.icons.reboot
        text: qsTr("Reboot")
        onClicked: SessionManager.reboot()
    }

    Action {
        icon: "desktop_windows"
        text: qsTr("Windows")
        visible: Config.session.commands.windows.length > 0
        disabled: root.failed
        onClicked: bootToWindows.running = true
    }

    Action {
        icon: Config.session.icons.shutdown
        text: qsTr("Shut down")
        destructive: true
        onClicked: SessionManager.poweroff()
    }

    component Action: IconTextButton {
        property bool destructive: false

        Layout.fillWidth: true

        type: IconTextButton.Tonal
        font: Tokens.font.body.small
        inactiveColour: destructive ? Colours.palette.m3errorContainer : Woodland.velvet
        inactiveOnColour: destructive ? Colours.palette.m3onErrorContainer : Woodland.ivory
    }
}
