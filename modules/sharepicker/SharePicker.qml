pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils

// Screen-share chooser for xdg-desktop-portal-hyprland. bin/burl-share-picker
// is XDPH's custom_picker_binary: it calls pick() and relays whatever reply()
// writes to its FIFO back to XDPH, so the reply must keep the stock
// hyprland-share-picker format, "[SELECTION]<flags>/<target>\n".
Scope {
    id: root

    property bool open
    property string replyPath
    property bool allowToken

    property var screens: []
    property string windowList
    // A binding, so previews attach once Hyprland's toplevel list arrives.
    readonly property var windows: root.parseWindows(root.windowList)
    readonly property var entries: root.screens.concat(root.windows)
    property int selectedIndex

    readonly property int cols: Math.max(1, Math.min(4, root.windows.length))

    // XDPH_WINDOW_SHARING_LIST: "<handle>[HC>]<class>[HT>]<title>[HE>]<address>[HA>]"
    // per window. The handle is what XDPH wants back; the address (decimal, 0
    // when unknown) finds the Hyprland toplevel to preview; addresses stay
    // below 2^53, and BigInt is missing from the QML engine.
    function parseWindows(list: string): var {
        const byAddress = new Map(Hypr.toplevels.values.map(t => [t.address, t]));
        const order = Hypr.mru;
        const rank = a => {
            const i = order.indexOf(a);
            return i < 0 ? order.length + 1 : i;
        };
        const out = [];
        for (const chunk of list.split("[HA>]")) {
            const m = chunk.match(/^(\d+)\[HC>\]([\s\S]*)\[HT>\]([\s\S]*)\[HE>\](\d+)$/);
            if (!m)
                continue;
            const address = m[4] === "0" ? "" : Number(m[4]).toString(16);
            const toplevel = byAddress.get(address) ?? null;
            const ws = toplevel?.workspace?.name ?? "";
            out.push({
                source: toplevel?.wayland ?? null,
                title: m[3] || m[2],
                detail: ws.startsWith("special:") ? ws.slice(8) : ws,
                icon: Icons.getAppIcon(m[2], "image-missing"),
                target: `window:${m[1]}`,
                rank: rank(address)
            });
        }
        return out.sort((a, b) => a.rank - b.rank);
    }

    function pick(path: string, allowToken: bool, windowList: string): void {
        if (root.replyPath)
            root.reply("");
        root.replyPath = path;
        root.allowToken = allowToken;
        root.screens = Quickshell.screens.map(s => ({
                    source: s,
                    title: s.name,
                    detail: `${s.width}×${s.height}`,
                    icon: Quickshell.iconPath("video-display", "image-missing"),
                    target: `screen:${s.name}`
                }));
        root.windowList = windowList;
        const focused = Hypr.focusedMonitor?.name;
        root.selectedIndex = Math.max(0, root.screens.findIndex(s => s.title === focused));
        root.open = true;
    }

    // An empty reply has no [SELECTION] marker, which XDPH treats as cancel.
    function reply(target: string): void {
        const path = root.replyPath;
        root.replyPath = "";
        root.open = false;
        if (!path)
            return;
        const text = target ? `[SELECTION]${root.allowToken ? "r" : ""}/${target}\n` : "";
        // The timeout keeps an orphaned writer from blocking forever if the
        // picker script already gave up and nobody reads the FIFO.
        Quickshell.execDetached(["timeout", "5", "sh", "-c", 'printf "%s" "$1" > "$2"', "sh", text, path]);
    }

    function choose(): void {
        const e = root.entries[root.selectedIndex];
        if (e)
            root.reply(e.target);
    }

    function pickRegion(): void {
        // Started before closing: closing destroys the window whose key
        // handler is running this.
        regionProc.running = true;
        root.open = false;
    }

    function step(delta: int): void {
        const n = root.entries.length;
        if (n > 0)
            root.selectedIndex = (root.selectedIndex + delta + n) % n;
    }

    function vertical(down: bool): void {
        const i = root.selectedIndex;
        const nS = root.screens.length;
        const n = root.entries.length;
        if (down) {
            if (i < nS && n > nS)
                root.selectedIndex = nS + Math.min(i, root.cols - 1, n - nS - 1);
            else if (i >= nS && i + root.cols < n)
                root.selectedIndex = i + root.cols;
        } else if (i >= nS) {
            const w = i - nS;
            root.selectedIndex = w < root.cols ? Math.min(w, nS - 1) : i - root.cols;
        }
    }

    // slurp prints global logical coordinates; XDPH wants them relative to
    // the output, like the stock picker sends.
    Process {
        id: regionProc

        command: ["slurp", "-f", "%o %x %y %w %h"]
        stdout: StdioCollector {
            // Cancelling slurp prints nothing, which falls through to a cancel.
            onStreamFinished: {
                const [name, x, y, w, h] = text.trim().split(" ");
                const mon = Hypr.monitors.values.find(m => m.name === name);
                if (!mon || !(w > 0 && h > 0))
                    root.reply("");
                else
                    root.reply(`region:${name}@${x - mon.x},${y - mon.y},${w},${h}`);
            }
        }
    }

    IpcHandler {
        function pick(path: string, allowToken: bool, windowList: string): string {
            root.pick(path, allowToken, windowList);
            return "ready";
        }

        function cancel(): void {
            root.reply("");
        }

        target: "sharepicker"
    }

    LazyLoader {
        active: root.open

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData
                readonly property bool onFocused: Hypr.monitorFor(modelData)?.id === Hypr.focusedMonitor?.id

                screen: modelData
                name: "sharepicker"
                visible: onFocused
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.exclusionMode: ExclusionMode.Ignore

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(Woodland.barkEdge, 0.62)
                    focus: true

                    Component.onCompleted: forceActiveFocus()
                    onVisibleChanged: if (visible)
                        forceActiveFocus()

                    Keys.onEscapePressed: root.reply("")
                    Keys.onReturnPressed: root.choose()
                    Keys.onEnterPressed: root.choose()
                    Keys.onLeftPressed: root.step(-1)
                    Keys.onRightPressed: root.step(1)
                    Keys.onTabPressed: root.step(1)
                    Keys.onBacktabPressed: root.step(-1)
                    Keys.onUpPressed: root.vertical(false)
                    Keys.onDownPressed: root.vertical(true)
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_R) {
                            root.pickRegion();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_T) {
                            root.allowToken = !root.allowToken;
                            event.accepted = true;
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.reply("")
                    }

                    WoodPanel {
                        id: panel

                        readonly property real cellW: 300
                        readonly property real cellH: 200
                        readonly property real gridW: root.cols * cellW + (root.cols - 1) * Tokens.spacing.medium
                        readonly property real screensW: root.screens.length * (cellW + Tokens.spacing.medium) - Tokens.spacing.medium

                        anchors.centerIn: parent

                        implicitWidth: Math.min(parent.width - Tokens.padding.large * 4, Math.max(gridW, screensW, footer.implicitWidth) + Tokens.padding.large * 2)
                        implicitHeight: content.implicitHeight + Tokens.padding.large * 2

                        radius: Tokens.rounding.extraLarge
                        framed: true
                        fill: Colours.palette.m3surfaceContainer

                        MouseArea {
                            anchors.fill: parent
                        }

                        Column {
                            id: content

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.large
                            spacing: Tokens.spacing.medium

                            StyledText {
                                width: parent.width
                                text: qsTr("Share your screen")
                                color: Woodland.creamPrimary
                                font: Tokens.font.title.medium
                            }

                            StyledText {
                                text: qsTr("Screens")
                                color: Woodland.creamSecondary
                                font: Tokens.font.label.large
                            }

                            Row {
                                x: (parent.width - width) / 2
                                spacing: Tokens.spacing.medium

                                Repeater {
                                    model: root.screens

                                    Card {
                                        required property int index
                                        required property var modelData

                                        width: panel.cellW
                                        height: panel.cellH
                                        source: modelData.source
                                        title: modelData.title
                                        detail: modelData.detail
                                        icon: modelData.icon
                                        selected: index === root.selectedIndex

                                        onHovered: root.selectedIndex = index
                                        onActivated: root.reply(modelData.target)
                                    }
                                }
                            }

                            StyledText {
                                visible: root.windows.length > 0
                                text: qsTr("Windows")
                                color: Woodland.creamSecondary
                                font: Tokens.font.label.large
                            }

                            StyledFlickable {
                                id: flick

                                visible: root.windows.length > 0
                                width: parent.width
                                height: Math.min(grid.implicitHeight, win.height * 0.45)
                                contentHeight: grid.implicitHeight
                                clip: true

                                Column {
                                    id: grid

                                    readonly property int rows: Math.ceil(root.windows.length / root.cols)

                                    x: (flick.width - panel.gridW) / 2
                                    width: panel.gridW
                                    spacing: Tokens.spacing.medium

                                    Repeater {
                                        model: grid.rows

                                        // Rows by hand: a Grid left-aligns a short last row.
                                        Row {
                                            id: rowItem

                                            required property int index

                                            x: (grid.width - width) / 2
                                            spacing: Tokens.spacing.medium

                                            Repeater {
                                                model: root.windows.slice(rowItem.index * root.cols, (rowItem.index + 1) * root.cols)

                                                Card {
                                                    id: card

                                                    required property int index
                                                    required property var modelData
                                                    readonly property int flatIndex: root.screens.length + rowItem.index * root.cols + card.index

                                                    width: panel.cellW
                                                    height: panel.cellH
                                                    source: modelData.source
                                                    title: modelData.title
                                                    detail: modelData.detail
                                                    icon: modelData.icon
                                                    selected: flatIndex === root.selectedIndex

                                                    onSelectedChanged: {
                                                        if (!selected)
                                                            return;
                                                        const top = rowItem.y;
                                                        if (top < flick.contentY)
                                                            flick.contentY = top;
                                                        else if (top + height > flick.contentY + flick.height)
                                                            flick.contentY = top + height - flick.height;
                                                    }
                                                    onHovered: root.selectedIndex = flatIndex
                                                    onActivated: root.reply(modelData.target)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Row {
                                id: footer

                                anchors.right: parent.right
                                spacing: Tokens.spacing.medium

                                StyledSwitch {
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: root.allowToken
                                    onToggled: root.allowToken = checked
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Let this app share again without asking (T)")
                                    color: Woodland.creamSecondary
                                    font: Tokens.font.label.medium
                                }

                                TextButton {
                                    type: ButtonBase.Tonal
                                    text: qsTr("Region… (R)")
                                    onClicked: root.pickRegion()
                                }

                                TextButton {
                                    type: ButtonBase.Text
                                    text: qsTr("Cancel")
                                    onClicked: root.reply("")
                                }

                                TextButton {
                                    text: qsTr("Share")
                                    onClicked: root.choose()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
