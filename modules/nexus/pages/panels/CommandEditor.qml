pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.controls
import qs.modules.nexus.common
import qs.services
import "../../../launcher/services/CommandArguments.js" as CommandArguments
import "../../../launcher/SearchQuery.js" as SearchQuery

ColumnLayout {
    id: root

    property int editingIndex: -1
    property bool editing: false
    property var original: ({})
    property string error: ""
    readonly property bool internalCommand: ["autocomplete", "setText", "setMode"].includes(executable.text.trim())
    visible: editing
    spacing: Tokens.spacing.medium

    function begin(index: int): void {
        editingIndex = index;
        original = index >= 0 ? JSON.parse(JSON.stringify(GlobalConfig.launcher.actions[index])) : {};
        nameField.text = original.name ?? "";
        keyword.text = index >= 0 ? CommandArguments.keywordFor(original) : "";
        description.text = original.description ?? "";
        executable.text = original.command?.[0] ?? "";
        argumentsField.text = CommandArguments.formatArguments((original.command ?? []).slice(1));
        extraArgs.checked = original.acceptArgs ?? false;
        actionEnabled.checked = original.enabled ?? true;
        dangerous.checked = original.dangerous ?? false;
        error = "";
        editing = true;
        nameField.forceActiveFocus();
    }

    function unchanged(): bool {
        if (editingIndex < 0 || JSON.stringify(GlobalConfig.launcher.actions[editingIndex]) === JSON.stringify(original))
            return true;
        error = qsTr("This command changed elsewhere. Cancel and reopen it before saving.");
        return false;
    }

    function save(): bool {
        error = "";
        const name = nameField.text.trim();
        const key = keyword.text.trim().toLowerCase();
        const program = executable.text.trim();
        const args = CommandArguments.parseArguments(argumentsField.text);
        if (!name || !program) {
            error = qsTr("Enter a name and executable.");
            return false;
        }
        if (!/^[a-z0-9][a-z0-9_-]*$/.test(key)) {
            error = qsTr("Use letters, numbers, hyphens or underscores for the keyword.");
            return false;
        }
        const existingKey = editingIndex >= 0 ? CommandArguments.keywordFor(original).toLowerCase() : "";
        if ((SearchQuery.kindsFor(key) || key === "calc") && !(internalCommand && key === existingKey)) {
            error = qsTr("This keyword is reserved for a search filter or calculator.");
            return false;
        }
        const actions = Array.from(GlobalConfig.launcher.actions);
        if (actions.some((action, index) => index !== editingIndex && CommandArguments.keywordFor(action).toLowerCase() === key)) {
            error = qsTr("Another command already uses this keyword.");
            return false;
        }
        if (args.error) {
            error = args.error;
            return false;
        }
        if (!unchanged()) return false;
        const action = Object.assign({}, original, {
            name, keyword: key, description: description.text.trim(), command: [program].concat(args.args),
            acceptArgs: internalCommand ? false : extraArgs.checked, enabled: actionEnabled.checked, dangerous: dangerous.checked,
            icon: original.icon ?? "terminal"
        });
        if (editingIndex < 0) actions.push(action);
        else actions[editingIndex] = action;
        GlobalConfig.launcher.actions = actions;
        editing = false;
        return true;
    }

    function remove(): bool {
        if (editingIndex < 0 || !unchanged()) return false;
        const actions = Array.from(GlobalConfig.launcher.actions);
        actions.splice(editingIndex, 1);
        GlobalConfig.launcher.actions = actions;
        editing = false;
        return true;
    }

    StyledTextField {
        id: nameField
        objectName: "commandName"
        Layout.fillWidth: true
        placeholderText: qsTr("Name")
        Accessible.name: placeholderText
    }
    StyledTextField {
        id: keyword
        objectName: "commandKeyword"
        Layout.fillWidth: true
        placeholderText: qsTr("Keyword")
        supportingText: qsTr("Type %1%2 in the launcher").arg(GlobalConfig.launcher.actionPrefix).arg(text || "keyword")
        Accessible.name: placeholderText
    }
    StyledTextField {
        id: description
        objectName: "commandDescription"
        Layout.fillWidth: true
        placeholderText: qsTr("Description (optional)")
        Accessible.name: placeholderText
    }
    StyledTextField {
        id: executable
        objectName: "commandExecutable"
        Layout.fillWidth: true
        placeholderText: root.internalCommand ? qsTr("Built-in operation") : qsTr("Executable")
        supportingText: root.internalCommand ? qsTr("Burl handles this operation internally.") : qsTr("Program name or absolute path")
        Accessible.name: placeholderText
    }
    StyledTextField {
        id: argumentsField
        objectName: "commandArguments"
        Layout.fillWidth: true
        placeholderText: qsTr("Default arguments (optional)")
        supportingText: qsTr("Quote arguments containing spaces. Variables, pipes and substitutions stay literal.")
        Accessible.name: placeholderText
    }
    ToggleRow {
        id: extraArgs
        objectName: "commandAcceptArgs"
        first: true
        text: qsTr("Allow extra arguments")
        enabled: !root.internalCommand
        subtext: root.internalCommand ? qsTr("This built-in operation does not accept extra arguments.") : qsTr("Append text typed after the exact keyword")
    }
    ToggleRow {
        id: actionEnabled
        objectName: "commandEnabled"
        text: qsTr("Enabled")
    }
    ToggleRow {
        id: dangerous
        objectName: "commandDangerous"
        last: true
        text: qsTr("Requires dangerous actions enabled")
        subtext: qsTr("For commands that shut down or log out")
    }
    StyledText {
        objectName: "commandError"
        Layout.fillWidth: true
        visible: root.error !== ""
        text: root.error
        color: Colours.palette.m3error
        wrapMode: Text.Wrap
        Accessible.role: Accessible.AlertMessage
        Accessible.name: text
    }
    RowLayout {
        Layout.fillWidth: true
        IconTextButton {
            objectName: "commandSave"
            icon: "save"
            text: qsTr("Save")
            onClicked: root.save()
        }
        IconTextButton {
            icon: "close"
            text: qsTr("Cancel")
            type: ButtonBase.Tonal
            onClicked: root.editing = false
        }
        Item { Layout.fillWidth: true }
        IconTextButton {
            objectName: "commandDelete"
            visible: root.editingIndex >= 0
            icon: "delete"
            text: qsTr("Delete")
            type: ButtonBase.Tonal
            onClicked: root.remove()
        }
    }
}
