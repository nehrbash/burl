pragma ComponentBehavior: Bound

import Quickshell
import qs.components.filedialog
import qs.utils

// The profile-picture chooser Dash's User card opens. A component of its own
// because Content.qml requires one and Content is now mounted in two places —
// the dashboard drawer and the launcher's world tree — and neither host should
// be carrying a copy of the copy-and-notify logic.
FileDialog {
    id: root

    title: qsTr("Select a profile picture")
    filterLabel: qsTr("Image files")
    filters: Images.validImageExtensions
    onAccepted: path => {
        if (CUtils.copyFile(Qt.resolvedUrl(path), Qt.resolvedUrl(`${Paths.home}/.face`)))
            Quickshell.execDetached(["notify-send", "-a", "burl-shell", "-u", "low", "-h", `STRING:image-path:${path}`, "Profile picture changed", `Profile picture changed to ${Paths.shortenHome(path)}`]);
        else
            Quickshell.execDetached(["notify-send", "-a", "burl-shell", "-u", "critical", "Unable to change profile picture", `Failed to change profile picture to ${Paths.shortenHome(path)}`]);
    }
}
