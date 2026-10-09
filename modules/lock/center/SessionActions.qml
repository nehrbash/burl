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

// Power actions on the lock screen. This surface is also the greeter on a warm
// login (systems/redfish.scm #:warm-login-user), so without these the only way
// to shut the machine down before authenticating is the power button.
//
// Logout/switch-user are deliberately absent: there is one user and the session
// behind the lock is the one you want back.
RowLayout {
    id: root

    spacing: Tokens.spacing.small

    // Flip the firmware's one-shot BootNext, then reboot through logind so
    // inhibitors still get their say. The helper needs root; see the NOPASSWD
    // rule in systems/redfish.scm. `sudo -n` so a misconfigured rule fails
    // immediately instead of hanging on a prompt nobody can see.
    Process {
        id: bootToWindows

        command: ["sudo", "-n", "/run/current-system/profile/bin/boot-to-windows"]
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
        // Nothing to select if the firmware has no such entry, and the helper
        // would just exit non-zero — but the button still reads as broken, so
        // say so once it has actually failed.
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
