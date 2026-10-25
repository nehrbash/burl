import QtQuick
import QtQuick.Controls as Controls
import Burl.Config
import qs.components.controls

IconButton {
    id: root

    required property string description

    type: IconButton.Text
    implicitWidth: 36
    implicitHeight: 36
    font: Tokens.font.icon.small
    disabled: !enabled
    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: description
    Keys.onSpacePressed: if (enabled) clicked()
    Keys.onReturnPressed: if (enabled) clicked()
    Controls.ToolTip.visible: hovered || activeFocus
    Controls.ToolTip.text: description
    Controls.ToolTip.delay: 400
}
