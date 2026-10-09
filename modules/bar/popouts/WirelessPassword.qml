pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property PopoutState popouts
    property var network: null
    property bool isClosing: false

    // Dialog sheet warmed toward bark/parchment; buttons and focus borders
    // stay m3 so the wallpaper palette drives interaction
    readonly property color woodContainer: Colours.tPalette.m3surfaceContainer

    readonly property bool shouldBeVisible: root.popouts.currentName === "wirelesspassword"

    function checkConnectionStatus(): void {
        if (!root.shouldBeVisible || !connectButton.connecting) {
            return;
        }

        const isConnected = root.network && Nmcli.active && Nmcli.active.ssid && Nmcli.active.ssid.toLowerCase().trim() === root.network.ssid.toLowerCase().trim();

        if (isConnected) {
            connectionSuccessTimer.start();
            return;
        }

        if (Nmcli.pendingConnection === null && connectButton.connecting) {
            if (connectionMonitor.repeatCount > 10) {
                connectionMonitor.stop();
                connectButton.connecting = false;
                connectButton.hasError = true;
                passwordContainer.passwordBuffer = "";
                if (root.network && root.network.ssid) {
                    Nmcli.forgetNetwork(root.network.ssid);
                }
            }
        }
    }

    function closeDialog(): void {
        if (isClosing) {
            return;
        }

        isClosing = true;
        passwordContainer.passwordBuffer = "";
        connectButton.connecting = false;
        connectButton.hasError = false;
        connectionMonitor.stop();

        if (root.popouts.currentName === "wirelesspassword") {
            root.popouts.currentName = "network";
        }
    }

    spacing: Tokens.spacing.medium
    implicitWidth: 400
    implicitHeight: content.implicitHeight + Tokens.padding.extraLargeIncreased
    visible: shouldBeVisible || isClosing
    enabled: shouldBeVisible && !isClosing
    focus: enabled

    Component.onCompleted: {
        if (shouldBeVisible) {
            focusTimer.start();
        }
    }

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            focusTimer.start();
        }
    }

    Keys.onEscapePressed: closeDialog()

    Connections {
        function onCurrentNameChanged() {
            if (root.popouts.currentName === "wirelesspassword") {
                Qt.callLater(() => {
                    const content = root.parent?.parent?.parent;
                    if (content) {
                        const networkPopout = content.children.find(c => c.name === "network");
                        if (networkPopout && networkPopout.item) {
                            root.network = networkPopout.item.passwordNetwork;
                        }
                    }
                    focusTimer.start();
                });
            }
        }

        target: root.popouts
    }

    Timer {
        id: focusTimer

        interval: 150
        onTriggered: {
            root.forceActiveFocus();
            passwordContainer.forceActiveFocus();
        }
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.preferredWidth: 400
        implicitHeight: content.implicitHeight + Tokens.padding.extraLargeIncreased
        radius: Tokens.rounding.large
        color: root.woodContainer
        visible: root.shouldBeVisible || root.isClosing
        opacity: root.shouldBeVisible && !root.isClosing ? 1 : 0
        scale: root.shouldBeVisible && !root.isClosing ? 1 : 0.7
        Keys.onEscapePressed: root.closeDialog()

        WoodPanel {
            anchors.fill: parent
            radius: Tokens.rounding.large
            framed: true
            frameWidth: 4
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }

        ParallelAnimation {
            running: root.isClosing
            onFinished: {
                if (root.isClosing) {
                    root.isClosing = false;
                }
            }

            Anim {
                type: Anim.DefaultEffects
                target: parent
                property: "opacity"
                to: 0
            }
            Anim {
                target: parent
                property: "scale"
                to: 0.7
            }
        }

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.padding.large

            spacing: Tokens.spacing.medium

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "lock"
                fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).build()
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Enter password")
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                id: networkNameText

                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (root.network) {
                        const ssid = root.network.ssid;
                        if (ssid && ssid.length > 0) {
                            return qsTr("Network: %1").arg(ssid);
                        }
                    }
                    return qsTr("Network: Unknown");
                }
                color: Colours.palette.m3outline
                font: Tokens.font.body.small
            }

            Timer {
                property int attempts: 0

                interval: 50
                running: root.shouldBeVisible && (!root.network || !root.network.ssid)
                repeat: true
                onTriggered: {
                    attempts++;
                    const content = root.parent?.parent?.parent;
                    if (content) {
                        const networkPopout = content.children.find(c => c.name === "network");
                        if (networkPopout && networkPopout.item && networkPopout.item.passwordNetwork) {
                            root.network = networkPopout.item.passwordNetwork;
                        }
                    }
                    if ((root.network && root.network.ssid) || attempts >= 20) {
                        stop();
                        attempts = 0;
                    }
                }
                onRunningChanged: {
                    if (!running) {
                        attempts = 0;
                    }
                }
            }

            StyledText {
                id: statusText

                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.small
                visible: connectButton.connecting || connectButton.hasError
                text: {
                    if (connectButton.hasError) {
                        return qsTr("Connection failed. Please check your password and try again.");
                    }
                    if (connectButton.connecting) {
                        return qsTr("Connecting...");
                    }
                    return "";
                }
                color: connectButton.hasError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.small.weight(Font.Normal).build()
                wrapMode: Text.WordWrap
                Layout.maximumWidth: parent.width - Tokens.padding.extraLargeIncreased
            }

            FocusScope {
                id: passwordContainer

                property string passwordBuffer: ""

                objectName: "passwordContainer"
                Layout.topMargin: Tokens.spacing.largeIncreased
                Layout.fillWidth: true
                implicitHeight: Math.max(48, charList.implicitHeight + Tokens.padding.medium * 2)
                focus: true
                activeFocusOnTab: true

                Component.onCompleted: {
                    if (root.shouldBeVisible) {
                        passwordFocusTimer.start();
                    }
                }

                Keys.onPressed: event => {
                    if (!activeFocus) {
                        forceActiveFocus();
                    }

                    if (event.key === Qt.Key_Escape) {
                        event.accepted = false;
                        closeDialog();
                    }

                    if (connectButton.hasError && event.text && event.text.length > 0) {
                        connectButton.hasError = false;
                    }

                    if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                        if (connectButton.enabled) {
                            connectButton.clicked();
                        }
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backspace) {
                        if (event.modifiers & Qt.ControlModifier) {
                            passwordBuffer = "";
                        } else {
                            passwordBuffer = passwordBuffer.slice(0, -1);
                        }
                        event.accepted = true;
                    } else if (event.text && event.text.length > 0) {
                        if (event.key === Qt.Key_Tab) {
                            event.accepted = false;
                            return;
                        }
                        passwordBuffer += event.text;
                        event.accepted = true;
                    }
                }

                Connections {
                    function onShouldBeVisibleChanged(): void {
                        if (root.shouldBeVisible) {
                            passwordFocusTimer.start();
                            passwordContainer.passwordBuffer = "";
                            connectButton.hasError = false;
                        }
                    }

                    target: root
                }

                Timer {
                    id: passwordFocusTimer

                    interval: 50
                    onTriggered: {
                        passwordContainer.forceActiveFocus();
                    }
                }

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.large
                    color: passwordContainer.activeFocus ? Qt.lighter(root.woodContainer, 1.05) : root.woodContainer
                    border.width: passwordContainer.activeFocus || connectButton.hasError ? 4 : (root.shouldBeVisible ? 1 : 0)
                    border.color: {
                        if (connectButton.hasError) {
                            return Colours.palette.m3error;
                        }
                        if (passwordContainer.activeFocus) {
                            return Colours.palette.m3primary;
                        }
                        return root.shouldBeVisible ? Colours.palette.m3outline : "transparent";
                    }

                    Behavior on border.color {
                        CAnim {}
                    }

                    Behavior on border.width {
                        CAnim {}
                    }

                    Behavior on color {
                        CAnim {}
                    }
                }

                StateLayer {
                    hoverEnabled: false
                    cursorShape: Qt.IBeamCursor
                    radius: Tokens.rounding.large
                    onClicked: passwordContainer.forceActiveFocus()
                }

                StyledText {
                    id: placeholder

                    anchors.centerIn: parent
                    text: qsTr("Password")
                    color: Colours.palette.m3outline
                    font: Tokens.font.mono.medium
                    opacity: passwordContainer.passwordBuffer ? 0 : 1

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                ListView {
                    id: charList

                    readonly property int fullWidth: count * (implicitHeight + spacing) - spacing

                    anchors.centerIn: parent
                    implicitWidth: fullWidth
                    implicitHeight: Tokens.font.body.medium.pointSize

                    orientation: Qt.Horizontal
                    spacing: Tokens.spacing.extraSmall
                    interactive: false

                    model: ScriptModel {
                        values: passwordContainer.passwordBuffer.split("")
                    }

                    delegate: StyledRect {
                        id: ch

                        implicitWidth: implicitHeight
                        implicitHeight: charList.implicitHeight

                        color: Colours.palette.m3onSurface
                        radius: Tokens.rounding.medium / 2

                        opacity: 0
                        scale: 0
                        Component.onCompleted: {
                            opacity = 1;
                            scale = 1;
                        }
                        ListView.onRemove: removeAnim.start()

                        SequentialAnimation {
                            id: removeAnim

                            PropertyAction {
                                target: ch
                                property: "ListView.delayRemove"
                                value: true
                            }
                            ParallelAnimation {
                                Anim {
                                    type: Anim.DefaultEffects
                                    target: ch
                                    property: "opacity"
                                    to: 0
                                }
                                Anim {
                                    target: ch
                                    property: "scale"
                                    to: 0.5
                                }
                            }
                            PropertyAction {
                                target: ch
                                property: "ListView.delayRemove"
                                value: false
                            }
                        }

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }

                        Behavior on scale {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }
                    }

                    Behavior on implicitWidth {
                        Anim {}
                    }
                }
            }

            RowLayout {
                Layout.topMargin: Tokens.spacing.medium
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                TextButton {
                    id: cancelButton

                    Layout.fillWidth: true
                    Layout.minimumHeight: Tokens.font.body.medium.pointSize + Tokens.padding.medium * 2
                    inactiveColour: Colours.palette.m3secondaryContainer
                    inactiveOnColour: Colours.palette.m3onSecondaryContainer
                    text: qsTr("Cancel")

                    onClicked: root.closeDialog()
                }

                TextButton {
                    id: connectButton

                    property bool connecting: false
                    property bool hasError: false

                    Layout.fillWidth: true
                    Layout.minimumHeight: Tokens.font.body.medium.pointSize + Tokens.padding.medium * 2
                    inactiveColour: Colours.palette.m3primary
                    inactiveOnColour: Colours.palette.m3onPrimary
                    // Both derived from `connecting` — an imperative write to
                    // either would replace the binding for good, and the
                    // success path has nothing to restore it from, so the
                    // button stayed disabled for the rest of the session after
                    // the first network that asked for a password.
                    text: connecting ? qsTr("Connecting...") : qsTr("Connect")
                    enabled: passwordContainer.passwordBuffer.length > 0 && !connecting

                    onClicked: {
                        if (!root.network || connecting) {
                            return;
                        }

                        const password = passwordContainer.passwordBuffer;
                        if (!password || password.length === 0) {
                            return;
                        }

                        hasError = false;
                        connecting = true;

                        NetworkConnection.connectWithPassword(root.network, password, result => {
                            // Success: the connection monitor takes it from here.
                            if (result && result.success)
                                return;

                            connectionMonitor.stop();
                            connecting = false;
                            hasError = true;
                            passwordContainer.passwordBuffer = "";
                            if (root.network && root.network.ssid) {
                                Nmcli.forgetNetwork(root.network.ssid);
                            }
                        });

                        connectionMonitor.start();
                    }
                }
            }
        }
    }

    Timer {
        id: connectionMonitor

        property int repeatCount: 0

        interval: 1000
        repeat: true
        triggeredOnStart: false

        onTriggered: {
            repeatCount++;
            root.checkConnectionStatus();
        }

        onRunningChanged: {
            if (!running) {
                repeatCount = 0;
            }
        }
    }

    Timer {
        id: connectionSuccessTimer

        interval: 500
        onTriggered: {
            if (root.shouldBeVisible && Nmcli.active && Nmcli.active.ssid) {
                const stillConnected = Nmcli.active.ssid.toLowerCase().trim() === root.network.ssid.toLowerCase().trim();
                if (stillConnected) {
                    connectionMonitor.stop();
                    connectButton.connecting = false;
                        if (root.popouts.currentName === "wirelesspassword") {
                        root.popouts.currentName = "network";
                    }
                    closeDialog();
                }
            }
        }
    }

    Connections {
        function onActiveChanged() {
            if (root.shouldBeVisible) {
                root.checkConnectionStatus();
            }
        }

        function onConnectionFailed(ssid: string) {
            if (root.shouldBeVisible && root.network && root.network.ssid === ssid && connectButton.connecting) {
                connectionMonitor.stop();
                connectButton.connecting = false;
                connectButton.hasError = true;
                passwordContainer.passwordBuffer = "";
                Nmcli.forgetNetwork(ssid);
            }
        }

        target: Nmcli
    }
}
