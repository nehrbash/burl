pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property var search       // StyledTextField — for read + autocomplete writes
    required property var visibilities

    // Exposed so Content.qml's Keys.onUp/Down can drive selection.
    readonly property alias list: list

    readonly property string prefix: GlobalConfig.launcher.actionPrefix
    // Kind-action (Embark-style) mode: when set, the overlay lists
    // per-node context actions instead of the global Actions.query().
    // Entries share the query result's shape ({name, desc, icon,
    // activate(search, vis)}) so the delegate below is unchanged.
    property bool inKindMode: false
    property var kindActions: []

    // `>scheme ` and `>variant ` (written by the Scheme/Variant actions)
    // list the choices themselves; the rest of the text filters them.
    readonly property string pickKind: ["scheme", "variant"].find(kind => search.text.startsWith(`${prefix}${kind} `)) ?? ""
    readonly property string pickFilter: pickKind ? search.text.slice(prefix.length + pickKind.length + 1).trim().toLowerCase() : ""
    onPickKindChanged: if (pickKind) Schemes.refresh()

    function close(visibilities: var): void {
        visibilities.closeWorld("dismiss");
    }

    readonly property var pickMatches: {
        const words = pickFilter.split(/\s+/).filter(word => word.length > 0);
        const wanted = label => words.every(word => label.toLowerCase().includes(word));
        if (pickKind === "scheme")
            return Schemes.entries.filter(entry => wanted(`${entry.name} ${entry.flavour}`)).map(entry => ({
                name: entry.flavour === "default" ? entry.name : `${entry.name} ${entry.flavour}`,
                desc: entry.name === Colours.scheme && entry.flavour === Colours.flavour ? qsTr("Current scheme") : qsTr("Colour scheme"),
                icon: "palette",
                activate: (search, visibilities) => {
                    Schemes.select(entry.name, entry.flavour);
                    root.close(visibilities);
                }
            }));
        if (pickKind === "variant")
            return Schemes.variants.filter(wanted).map(variant => ({
                name: variant,
                desc: variant === Schemes.variant ? qsTr("Current variant") : qsTr("Scheme variant"),
                icon: "colors",
                activate: (search, visibilities) => {
                    Schemes.selectVariant(variant);
                    root.close(visibilities);
                }
            }));
        return [];
    }

    readonly property var matches: pickKind
        ? pickMatches
        : inKindMode
        ? kindActions
        : Actions.query(search.text)

    function activateTop(): void {
        const m = matches[list.currentIndex] ?? matches[0];
        if (m)
            m.activate(search, visibilities);
    }

    readonly property bool hasContent: inKindMode || matches.length > 0
    visible: hasContent
    implicitWidth: 640
    implicitHeight: hasContent ? bg.implicitHeight : 0

    StyledRect {
        id: bg

        anchors.fill: parent
        // Parchment sheet in a carved-wood frame (WoodPanel below draws
        // the grain + bark border); base stays palette-derived so light/
        // dark wallpaper schemes still read through.
        color: Colours.layer(Colours.palette.m3surfaceContainer, 1)
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

        implicitHeight: Math.min(maxVisible, root.matches.length) * (Tokens.sizes.launcher.itemHeight + Tokens.spacing.small) + Tokens.padding.medium

        StyledListView {
            id: list

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
