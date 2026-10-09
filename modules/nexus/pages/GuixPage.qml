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
import qs.modules.nexus.common

PageBase {
    id: root

    // Guix Home also runs on hosts without Guix System.
    readonly property bool isGuixSystem: SysInfo.osId === "guix"
    readonly property var actions: GlobalConfig.guix.actions.filter(a => !a.guixSystemOnly || root.isGuixSystem)

    property bool logExpanded: false
    property var pendingConfirm: null
    property string searchQuery: ""
    readonly property var searchResults: Guix.search(root.searchQuery, 60)

    title: qsTr("Guix")

    Component.onCompleted: Guix.refreshChannels(false)

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ---------------------------------------------------------- channels
        SectionHeader {
            first: true
            text: qsTr("Channels")
        }

        Repeater {
            model: Guix.channels

            InfoRow {
                required property var modelData
                required property int index

                first: index === 0
                icon: modelData.current === true ? "check_circle" : modelData.behind > 0 ? "arrow_circle_up" : "help"
                iconColour: modelData.current === true ? Colours.palette.m3primary : modelData.behind > 0 ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant
                label: modelData.name
                // The commit is the useful identity; the URL is noise once you
                // know which channel it is, so it goes in the subtext.
                subtext: `${modelData.local.substring(0, 8)}${modelData.upstream ? " → " + modelData.upstream.substring(0, 8) : ""}  ·  ${modelData.branch}`
                value: {
                    if (modelData.upstream === null)
                        return qsTr("not checked");
                    if (modelData.current === true)
                        return qsTr("up to date");
                    if (modelData.behind === null)
                        return qsTr("differs");
                    return qsTr("%n commit(s) behind", "", modelData.behind);
                }
            }
        }

        InfoRow {
            last: true
            icon: "cloud_sync"
            label: qsTr("Compare with upstream")
            subtext: Guix.channelsLoading ? qsTr("checking…") : qsTr("Fetches each channel's remote — a few seconds")
            leadingComponent: null

            IconTextButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Tokens.padding.large

                icon: "refresh"
                text: Guix.channelsLoading ? qsTr("Checking…") : qsTr("Check")
                enabled: !Guix.channelsLoading
                onClicked: Guix.refreshChannels(true)
            }
        }

        // ----------------------------------------------------------- actions
        SectionHeader {
            text: qsTr("Rebuild")
        }

        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.small

            Repeater {
                model: root.actions

                IconTextButton {
                    required property var modelData

                    icon: modelData.icon ?? "play_arrow"
                    text: modelData.label ?? modelData.id
                    // One at a time: every one of these mutates a profile.
                    enabled: !Guix.runningAction && !Guix.gcBusy
                    onClicked: {
                        if (modelData.confirm)
                            root.pendingConfirm = modelData;
                        else
                            Guix.runAction(modelData);
                    }
                }
            }
        }

        // Confirmation for destructive/root actions (guix.actions `confirm').
        Loader {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            active: root.pendingConfirm !== null
            visible: active

            sourceComponent: RowLayout {
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Run “%1”? This needs root.").arg(root.pendingConfirm?.label ?? "")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }

                IconTextButton {
                    icon: "check"
                    text: qsTr("Run")
                    onClicked: {
                        const a = root.pendingConfirm;
                        root.pendingConfirm = null;
                        Guix.runAction(a);
                    }
                }

                IconTextButton {
                    icon: "close"
                    text: qsTr("Cancel")
                    onClicked: root.pendingConfirm = null
                }
            }
        }

        // ------------------------------------------------------------- store
        SectionHeader {
            text: qsTr("Store")
        }

        InfoRow {
            first: true
            last: true
            icon: "delete_sweep"
            label: qsTr("Collect garbage")
            subtext: {
                if (Guix.gcInfo?.text)
                    return qsTr("Last run freed %1 across %n item(s)", "", Guix.gcDeleted).arg(Guix.gcInfo.text);
                if (Guix.gcDeleted > 0)
                    return qsTr("%n item(s) deleted", "", Guix.gcDeleted);
                return qsTr("Deletes store items nothing references — can take many minutes");
            }

            IconTextButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Tokens.padding.large

                icon: "cleaning_services"
                text: Guix.gcBusy ? qsTr("Running…") : qsTr("Collect")
                enabled: !Guix.gcBusy && !Guix.runningAction
                onClicked: Guix.collectGarbage()
            }
        }

        // ---------------------------------------------------------- activity
        // Progress and the output pane come AFTER every button that writes to
        // them — pull, the rebuilds and gc all stream here, and having the log
        // sandwiched between those buttons made it read as belonging to
        // whichever one it happened to sit next to.
        SectionHeader {
            text: qsTr("Activity")
        }

        // Progress: indeterminate on purpose. Guix emits no machine-readable
        // percentage, so only the phase label is real.
        Loader {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            Layout.topMargin: Tokens.spacing.small
            active: Guix.runningAction !== null || Guix.gcBusy
            visible: active

            sourceComponent: ColumnLayout {
                spacing: Tokens.spacing.extraSmall

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const name = Guix.runningAction?.label ?? qsTr("Collecting garbage");
                            // gc names every path it deletes; the count is the
                            // signal, and logging each line froze the shell.
                            if (Guix.gcBusy && Guix.gcDeleted > 0)
                                return qsTr("%1 — %n item(s) deleted", "", Guix.gcDeleted).arg(name);
                            return Guix.phase.length > 0 ? `${name} — ${Guix.phase}` : name;
                        }
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    IconTextButton {
                        icon: "stop"
                        text: qsTr("Cancel")
                        visible: Guix.runningAction !== null
                        onClicked: Guix.cancelAction()
                    }
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    indeterminate: true
                }
            }
        }

        // Output pane: collapsed by default, because a successful rebuild's log
        // is noise and a failed one is the first thing you want.
        InfoRow {
            first: true
            last: !root.logExpanded
            icon: root.logExpanded ? "expand_less" : "expand_more"
            label: qsTr("Output")
            subtext: Guix.logLines.length > 0 ? qsTr("%n line(s)", "", Guix.logLines.length) : qsTr("Nothing run yet")
            value: Guix.lastExitCode !== 0 ? qsTr("exit %1").arg(Guix.lastExitCode) : ""

            StateLayer {
                anchors.fill: parent
                onClicked: root.logExpanded = !root.logExpanded
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            active: root.logExpanded
            visible: active

            sourceComponent: StyledRect {
                implicitHeight: Tokens.sizes.nexus.minPopupHeight
                radius: Tokens.rounding.small
                color: Woodland.surface(Colours.tPalette.m3surfaceContainerHigh, Colours.light)

                StyledFlickable {
                    id: logFlick

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    contentHeight: logText.implicitHeight
                    clip: true

                    StyledText {
                        id: logText

                        width: logFlick.width
                        text: Guix.logLines.join("\n")
                        font: Tokens.font.mono.small
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.NoWrap
                    }
                }

                // Follow the tail while something is running.
                Connections {
                    function onLogLinesChanged(): void {
                        if (Guix.runningAction || Guix.gcBusy)
                            logFlick.contentY = Math.max(0, logFlick.contentHeight - logFlick.height);
                    }

                    target: Guix
                }
            }
        }

        // ---------------------------------------------------------- packages
        SectionHeader {
            text: qsTr("Packages")
        }

        SearchBar {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large

            placeholderText: Guix.packagesLoading ? qsTr("Loading package list…") : qsTr("Search %n package(s)", "", Guix.allPackages.length)
            onTextChanged: root.searchQuery = text
            // 32.7k packages parsed once; filtering is a JS pass per keystroke.
            onActiveFocusChanged: if (activeFocus)
                Guix.refreshPackages()
        }

        Repeater {
            model: root.searchResults

            InfoRow {
                required property var modelData
                required property int index

                readonly property string source: Guix.sourceOf(modelData.name)

                first: index === 0
                last: index === root.searchResults.length - 1
                icon: source === "" ? "radio_button_unchecked" : "check_circle"
                iconColour: source === "home" ? Colours.palette.m3primary : source === "user" ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant
                label: modelData.name
                subtext: modelData.location
                // Which profile it came from is the interesting part: `home' is
                // declared in home/oceania.scm, `user' was `guix install'ed and
                // will not survive a fresh machine.
                value: {
                    if (source === "home")
                        return qsTr("%1 · home").arg(Guix.installedHome[modelData.name]);
                    if (source === "user")
                        return qsTr("%1 · ad-hoc").arg(Guix.installedUser[modelData.name]);
                    return modelData.version;
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: root.searchQuery.length > 0 && root.searchResults.length === 0 && !Guix.packagesLoading
            visible: active

            sourceComponent: StyledText {
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("No package matches “%1”").arg(root.searchQuery)
                color: Colours.palette.m3outlineVariant
                font: Tokens.font.body.small
            }
        }
    }
}
