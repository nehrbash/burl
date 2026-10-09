pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.components.widgets
import qs.services

// Screenshot history shelf: a 2-up grid of framed thumbnails, collapsed to the
// newest row, expanded to three scrollable rows. Chrome recipe (StyledRect +
// WoodPanel + BarkFrame + Tokens.padding.large margins) is copied verbatim from
// cards/Record.qml so the cards read as one shelf.
//
// Per-cell actions are the three that matter at a glance (recopy / edit /
// delete); the other three live in the preview overlay. Six icon buttons will
// not fit legibly inside a 183px cell, so they are not put there.
StyledRect {
    id: root

    required property var props
    required property ScreenState screenState

    readonly property int columns: 2
    readonly property real cellW: Math.max(1, Math.floor(grid.width / root.columns))
    readonly property real cellH: Math.round((root.cellW - Tokens.spacing.extraSmall * 2) * 9 / 16) + Tokens.spacing.extraSmall * 2
    // The un-animated target height, so the drawer's exclusion zone is sized
    // from where the grid is going, not from where the Behavior currently is.
    readonly property real gridHeight: root.cellH * (Screenshots.expanded ? 3 : 1)
    readonly property real nonAnimHeight: header.implicitHeight + divider.implicitHeight + root.gridHeight + layout.spacing * 2 + layout.anchors.margins * 2

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2

    radius: Tokens.rounding.large
    color: Woodland.surface(Colours.tPalette.m3surfaceContainer, Colours.light)

    WoodPanel {
        anchors.fill: parent
    }

    BarkFrame {
        anchors.fill: parent
        radius: parent.radius
        frameWidth: 3
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        WrapperMouseArea {
            id: header

            Layout.fillWidth: true

            cursorShape: Qt.PointingHandCursor
            onClicked: Screenshots.expanded = !Screenshots.expanded

            RowLayout {
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    text: "screenshot_monitor"
                    fontStyle: Tokens.font.icon.large
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    text: qsTr("Screenshots")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: `${Screenshots.entries.length}`
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    animate: true
                }

                IconButton {
                    icon: Screenshots.expanded ? "unfold_less" : "unfold_more"
                    type: IconButton.Text
                    label.animate: true
                    onClicked: Screenshots.expanded = !Screenshots.expanded
                }
            }
        }

        GrooveDivider {
            id: divider

            Layout.fillWidth: true
        }

        GridView {
            id: grid

            Layout.fillWidth: true
            implicitHeight: root.gridHeight

            model: Screenshots.entries
            cellWidth: root.cellW
            cellHeight: root.cellH
            clip: true
            // Collapsed the grid is a peek, not a scroller: flicking a 1-row
            // window that shows the only row the user asked for is noise.
            interactive: Screenshots.expanded
            flickableDirection: Flickable.VerticalFlick

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: grid
            }

            delegate: Item {
                id: cell

                required property var modelData

                readonly property bool current: Screenshots.previewPath === cell.modelData.path
                // Gated by the service so only one uncached full-res decode is
                // ever in flight — see Screenshots.qml's warm-up comment.
                readonly property bool allowed: Screenshots.mayWarm(cell.modelData.path)

                width: grid.cellWidth
                height: grid.cellHeight

                Component.onCompleted: Screenshots.requestWarm(cell.modelData.path)

                HoverHandler {
                    id: cellHover
                }

                StyledClippingRect {
                    id: pane

                    anchors.fill: parent
                    anchors.margins: Tokens.spacing.extraSmall

                    radius: Tokens.rounding.small
                    color: Woodland.mix(Woodland.barkShaded, Woodland.barkEdge, 0.4)

                    MouseArea {
                        anchors.fill: parent

                        // No hoverEnabled: cursorShape does not need it, and a
                        // hover-tracking MouseArea here would compete with the
                        // cell's HoverHandler for the strip's visibility.
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Screenshots.openPreview(cell.modelData.path)
                    }

                    Loader {
                        id: thumbLoader

                        anchors.fill: parent

                        asynchronous: true
                        active: cell.allowed

                        sourceComponent: CachingImage {
                            path: cell.modelData.path
                            fillMode: Image.PreserveAspectCrop
                            // The blob deform matrix scales content sub-pixel on
                            // a 240Hz panel; one mip level costs nothing at idle
                            // and kills the shimmer.
                            mipmap: true
                            onStatusChanged: {
                                if (status === Image.Ready || status === Image.Error)
                                    Screenshots.finishWarm(cell.modelData.path);
                            }
                        }
                    }

                    // No retry timer: a permanently unreadable file must not spin.
                    Loader {
                        anchors.centerIn: parent

                        asynchronous: true
                        active: (thumbLoader.item as Image)?.status === Image.Error

                        sourceComponent: MaterialIcon {
                            text: "broken_image"
                            color: Woodland.creamSecondary
                            fontStyle: Tokens.font.icon.large
                        }
                    }

                    // Absence reads as "not kept" on its own — an unsaved cell
                    // gets no second glyph to learn.
                    Loader {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Tokens.spacing.extraSmall

                        asynchronous: true
                        active: cell.modelData.saved

                        sourceComponent: StyledRect {
                            implicitWidth: badge.implicitWidth + Tokens.padding.small
                            implicitHeight: badge.implicitHeight + Tokens.padding.extraSmall

                            radius: Tokens.rounding.full
                            color: Woodland.rimShadow

                            MaterialIcon {
                                id: badge

                                anchors.centerIn: parent
                                text: "bookmark"
                                fill: 1
                                color: Woodland.oliveLight
                                fontStyle: Tokens.font.icon.small
                            }
                        }
                    }

                    // Hover strip. Two handlers deliberately: the strip carries
                    // its own so the buttons cannot dismiss the thing they sit
                    // on when the pointer moves off the cell's own hover area.
                    StyledRect {
                        id: strip

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        implicitHeight: stripLayout.implicitHeight + Tokens.padding.extraSmall

                        color: Woodland.rimShadow
                        opacity: cellHover.hovered || stripHover.hovered ? 1 : 0
                        visible: opacity > 0

                        HoverHandler {
                            id: stripHover
                        }

                        RowLayout {
                            id: stripLayout

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.extraSmall

                            IconButton {
                                icon: "content_copy"
                                type: IconButton.Text
                                font: Tokens.font.icon.small
                                onClicked: Screenshots.copyImage(cell.modelData.path)
                            }

                            IconButton {
                                icon: "draw"
                                type: IconButton.Text
                                font: Tokens.font.icon.small
                                onClicked: {
                                    root.screenState.utilities = false;
                                    root.screenState.sidebar = false;
                                    Screenshots.edit(cell.modelData.path);
                                }
                            }

                            IconButton {
                                icon: "bookmark_add"
                                type: IconButton.Text
                                font: Tokens.font.icon.small
                                visible: !cell.modelData.saved
                                onClicked: Screenshots.save(cell.modelData.path, cell.modelData.base)
                            }

                            IconButton {
                                icon: "delete_forever"
                                type: IconButton.Text
                                font: Tokens.font.icon.small
                                label.color: Colours.palette.m3error
                                stateLayer.color: Colours.palette.m3error
                                onClicked: root.props.screenshotConfirmDelete = cell.modelData.path
                            }
                        }

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }
                }

                // Selection/hover ring: interaction state stays Material You.
                // Bark and moss never signal selection.
                //
                // z above the BarkFrame below it: the frame's 3 rings occupy the
                // outer 3px of the same rect, so a lower-z ring is painted over
                // completely and the previewed cell reads as unselected.
                Rectangle {
                    anchors.fill: pane

                    z: 1
                    radius: pane.radius
                    color: "transparent"
                    border.width: 2
                    border.color: Woodland.brass
                    opacity: cell.current ? 1 : cellHover.hovered ? 0.5 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                BarkFrame {
                    anchors.fill: pane

                    radius: pane.radius
                    frameWidth: 2
                }
            }

            add: Transition {
                Anim {
                    type: Anim.DefaultEffects
                    property: "opacity"
                    from: 0
                    to: 1
                }
            }

            remove: Transition {
                Anim {
                    type: Anim.DefaultEffects
                    property: "opacity"
                    to: 0
                }
            }

            displaced: Transition {
                Anim {
                    type: Anim.DefaultEffects
                    property: "opacity"
                    to: 1
                }
                Anim {
                    properties: "x,y"
                }
            }

            // Collapsing back to one row must show the NEWEST row, not whatever
            // the user had scrolled to — the collapsed grid is not interactive,
            // so a stale contentY would be unrecoverable.
            Connections {
                function onExpandedChanged(): void {
                    if (!Screenshots.expanded)
                        grid.positionViewAtBeginning();
                }

                target: Screenshots
            }

            Behavior on implicitHeight {
                Anim {}
            }
        }
    }

    // Deliberately NOT a child of the GridView: a Flickable's declared children
    // land in its contentItem, which is zero-height at count 0, so the
    // centred-in-parent placeholder cards/RecordingList.qml uses ends up pinned
    // to the top-left corner instead of the middle of the view.
    Loader {
        // `parent: grid` reparents onto the Flickable ITSELF rather than its
        // contentItem (declared children of a Flickable go to the contentItem),
        // which is what makes centreing legal here — anchoring to `grid` from
        // root is not, since grid is a grandchild of root via the ColumnLayout.
        parent: grid
        anchors.centerIn: parent

        asynchronous: true
        opacity: grid.count === 0 ? 1 : 0
        active: opacity > 0

        sourceComponent: RowLayout {
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "no_photography"
                color: Woodland.creamSecondary
            }

            StyledText {
                text: qsTr("No screenshots yet")
                color: Woodland.creamSecondary
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
