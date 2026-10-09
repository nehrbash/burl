pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Burl
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher.services

// Action/calc overlay shown above the search bar when the user types the
// launcher action prefix (e.g. ">").
Item {
    id: root

    required property var search       // StyledTextField — for read + autocomplete writes
    required property var visibilities

    // Exposed so Content.qml's Keys.onUp/Down can drive selection.
    readonly property alias list: list

    readonly property string prefix: GlobalConfig.launcher.actionPrefix
    readonly property bool calcMode: search.text.startsWith(`${prefix}calc `)
    readonly property string calcExpr: calcMode ? search.text.slice(`${prefix}calc `.length) : ""

    // Kind-action (Embark-style) mode: when set, the overlay lists
    // per-node context actions instead of the global Actions.query().
    // Entries share the query result's shape ({name, desc, icon,
    // activate(search, vis)}) so the delegate below is unchanged.
    property bool inKindMode: false
    property var kindActions: []

    readonly property var matches: calcMode
        ? []
        : inKindMode
        ? kindActions
        : Actions.query(search.text)

    onCalcExprChanged: {
        if (calcExpr.length > 0)
            Qalculator.evalAsync(calcExpr);
    }

    function activateTop(): void {
        if (calcMode) {
            if (Qalculator.rawResult)
                Quickshell.execDetached(["wl-copy", Qalculator.rawResult]);
            visibilities.launcher = false;
            return;
        }
        const m = matches[list.currentIndex] ?? matches[0];
        if (m)
            m.activate(search, visibilities);
    }

    // Same width as the search bar so it stacks neatly. Collapse the
    // popup entirely when there are no matches and we're not in calc
    // mode — a zero-row list rendered just a sliver of background
    // which looked bad.
    readonly property bool hasContent: calcMode || inKindMode || matches.length > 0
    visible: hasContent
    implicitWidth: 640
    implicitHeight: hasContent ? bg.implicitHeight : 0

    StyledRect {
        id: bg

        anchors.fill: parent
        // Parchment sheet in a carved-wood frame (WoodPanel below draws
        // the grain + bark border); base stays palette-derived so light/
        // dark wallpaper schemes still read through.
        color: Woodland.surface(Colours.layer(Colours.palette.m3surfaceContainer, 1), Colours.light)
        radius: Tokens.rounding.large

        WoodPanel {
            anchors.fill: parent
            radius: bg.radius
            framed: true
            frameWidth: 4
            fill: Qt.alpha(Colours.palette.m3primaryContainer, 0.05)
        }

        // Visible action count cap. The list still holds all matches and
        // scrolls past this with arrow keys; this just bounds the popup
        // height so it doesn't eat the whole launcher.
        readonly property int maxVisible: 8

        implicitHeight: {
            if (root.calcMode)
                return calcRow.implicitHeight + Tokens.padding.large * 2;
            return Math.min(maxVisible, root.matches.length) * (Tokens.sizes.launcher.itemHeight + Tokens.spacing.small) + Tokens.padding.medium;
        }

        Item {
            id: calcRow

            visible: root.calcMode
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            implicitHeight: resultText.implicitHeight

            MaterialIcon {
                id: calcIcon

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "calculate"
                color: Colours.palette.m3primary
            }

            StyledText {
                id: resultText

                anchors.left: calcIcon.right
                anchors.leftMargin: Tokens.spacing.medium
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                text: Qalculator.result || qsTr("…")
                font.pointSize: Tokens.font.body.medium.pointSize
                elide: Text.ElideRight
            }
        }

        StyledListView {
            id: list

            visible: !root.calcMode
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            clip: true
            spacing: Tokens.spacing.small
            orientation: Qt.Vertical

            model: ScriptModel {
                values: root.matches
                onValuesChanged: list.currentIndex = 0
            }

            // Scroll the currentItem into view when arrow keys cross the
            // visible bottom/top edge. highlightFollowsCurrentItem is off
            // because we draw a custom highlight; this fills that gap.
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            highlightFollowsCurrentItem: false
            // Selection wash keeps the m3 interactive state over parchment.
            highlight: StyledRect {
                radius: Tokens.rounding.medium
                color: Colours.palette.m3primary
                opacity: 0.12
                y: list.currentItem?.y ?? 0
                implicitWidth: list.width
                implicitHeight: list.currentItem?.implicitHeight ?? 0
                Behavior on y { Anim { type: Anim.DefaultSpatial } }
            }

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                implicitHeight: Tokens.sizes.launcher.itemHeight
                anchors.left: parent?.left
                anchors.right: parent?.right

                StateLayer {
                    radius: Tokens.rounding.medium
                    onClicked: row.modelData?.activate(root.search, root.visibilities)
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData?.icon ?? "help_outline"
                        color: Colours.palette.m3primary
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 60

                        StyledText {
                            text: row.modelData?.name ?? ""
                            font.pointSize: Tokens.font.body.medium.pointSize
                        }
                        StyledText {
                            text: row.modelData?.desc ?? ""
                            font.pointSize: Tokens.font.body.small.pointSize
                            color: Colours.palette.m3outline
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                }
            }
        }
    }
}
