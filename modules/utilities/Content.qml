import "cards"
import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.components.images
import qs.components.widgets
import qs.services
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property var props
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property matrix4x4 deformMatrix

    readonly property real nonAnimHeight: idleInhibit.nonAnimHeight + hibernateAfterSleep.nonAnimHeight + record.nonAnimHeight + screenshots.nonAnimHeight + toggles.implicitHeight + layout.spacing * 4

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        IdleInhibit {
            id: idleInhibit

            objectName: "utilitiesKeepAwake"
        }

        IdleInhibit {
            id: hibernateAfterSleep

            objectName: "utilitiesHibernateAfterSleep"
            hibernateSetting: true
        }

        Record {
            id: record

            objectName: "utilitiesScreenRecorder"

            props: root.props
            screenState: root.screenState
            z: 1
        }

        ScreenshotHistory {
            id: screenshots

            objectName: "utilitiesScreenshots"

            props: root.props
            screenState: root.screenState
        }

        Toggles {
            id: toggles

            objectName: "utilitiesQuickToggles"

            screenState: root.screenState
            popouts: root.popouts
        }
    }

    // Screenshot preview overlay. Layered at Content level (the same trick the
    // delete modal uses) rather than as a new StyledWindow or dashboard tab: a
    // window needs new focus-grab rules and new IPC, and a dashboard tab would
    // be born stale against the world-tree navigation rewrite. 366px of drawer
    // width is enough for a legible preview, which is all "previewer" needs.
    //
    // `active` is bound to the derived previewIndex, so deleting the previewed
    // file closes this on its own — no cross-modal knowledge.
    Loader {
        id: preview

        anchors.fill: parent

        asynchronous: true
        opacity: Screenshots.previewPath ? 1 : 0
        active: opacity > 0

        sourceComponent: MouseArea {
            hoverEnabled: true
            onClicked: Screenshots.closePreview()

            StyledRect {
                anchors.fill: parent
                anchors.margins: -Tokens.padding.large
                anchors.rightMargin: -Tokens.padding.large - Config.border.thickness - parent.width * (1 - root.deformMatrix.m11) / 2
                anchors.bottomMargin: -Tokens.padding.large - Config.border.thickness - parent.height * 0.1

                topLeftRadius: Tokens.rounding.extraLarge
                color: Colours.palette.m3scrim
                opacity: 0.5
            }

            StyledRect {
                id: card

                // Sticky, not a plain binding: save() renames the file, so the
                // entry is momentarily absent from the list and a binding would
                // blank the lightbox mid-fade.
                property var entry: Screenshots.previewEntry

                Connections {
                    target: Screenshots

                    function onPreviewEntryChanged(): void {
                        if (Screenshots.previewEntry)
                            card.entry = Screenshots.previewEntry;
                    }
                }

                anchors.centerIn: parent

                width: Math.min(parent.width, Tokens.sizes.utilities.width - Tokens.padding.large * 4)
                implicitHeight: cardLayout.implicitHeight + Tokens.padding.large * 2

                radius: Tokens.rounding.extraLarge
                color: Colours.palette.m3surfaceContainerHigh
                scale: 0

                Component.onCompleted: {
                    scale = Qt.binding(() => Screenshots.previewPath ? 1 : 0);
                }

                WoodPanel {
                    anchors.fill: parent
                    radius: parent.radius
                    framed: true
                }

                MouseArea {
                    anchors.fill: parent
                }

                Elevation {
                    anchors.fill: parent
                    radius: parent.radius
                    z: -1
                    level: 3
                }

                ColumnLayout {
                    id: cardLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        StyledText {
                            Layout.fillWidth: true
                            text: card.entry?.label ?? ""
                            font: Tokens.font.body.medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            text: `${Screenshots.previewIndex + 1}/${Screenshots.entries.length}`
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        IconButton {
                            icon: "close"
                            type: IconButton.Text
                            onClicked: Screenshots.closePreview()
                        }
                    }

                    GrooveDivider {
                        Layout.fillWidth: true
                    }

                    // A fixed fit box, deliberately: these grabs are 7680x2160
                    // (dual 4K), so deriving the box height from the source
                    // aspect would either need paintedHeight (binding loop) or a
                    // hardcoded guess. A letterboxed picture in a bark frame
                    // reads as a mat, and is never wrong for any aspect.
                    StyledClippingRect {
                        id: previewPane

                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(width * 9 / 16)

                        radius: Tokens.rounding.small
                        color: Colours.palette.m3surfaceContainerHighest

                        CachingImage {
                            anchors.fill: parent

                            path: card.entry?.path ?? ""
                            fillMode: Image.PreserveAspectFit
                            mipmap: true
                        }

                        // Inside the clipper on purpose: the bark edge is
                        // clipped to the same rounded rect the picture is, so
                        // the frame reads as carved around it.
                        BarkFrame {
                            anchors.fill: parent

                            radius: previewPane.radius
                            frameWidth: 2
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.extraSmall
                        spacing: Tokens.spacing.extraSmall

                        IconButton {
                            icon: "chevron_left"
                            type: IconButton.Text
                            disabled: Screenshots.previewIndex <= 0
                            onClicked: Screenshots.stepPreview(-1)
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        IconButton {
                            icon: "content_copy"
                            type: IconButton.Text
                            onClicked: Screenshots.copyImage(card.entry?.path ?? "")
                        }

                        IconButton {
                            icon: "draw"
                            type: IconButton.Text
                            onClicked: {
                                root.screenState.utilities = false;
                                root.screenState.sidebar = false;
                                Screenshots.closePreview();
                                Screenshots.edit(card.entry?.path ?? "");
                            }
                        }

                        IconButton {
                            icon: "bookmark_add"
                            type: IconButton.Text
                            visible: !(card.entry?.saved ?? true)
                            onClicked: Screenshots.save(card.entry?.path ?? "", card.entry?.base ?? "")
                        }

                        IconButton {
                            icon: "folder_open"
                            type: IconButton.Text
                            onClicked: {
                                root.screenState.utilities = false;
                                root.screenState.sidebar = false;
                                Screenshots.closePreview();
                                Screenshots.reveal(card.entry?.parentDir ?? "");
                            }
                        }

                        IconButton {
                            icon: "link"
                            type: IconButton.Text
                            onClicked: Screenshots.copyPath(card.entry?.path ?? "")
                        }

                        IconButton {
                            icon: "delete_forever"
                            type: IconButton.Text
                            label.color: Colours.palette.m3error
                            stateLayer.color: Colours.palette.m3error
                            onClicked: root.props.screenshotConfirmDelete = card.entry?.path ?? ""
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        IconButton {
                            icon: "chevron_right"
                            type: IconButton.Text
                            disabled: Screenshots.previewIndex < 0 || Screenshots.previewIndex >= Screenshots.entries.length - 1
                            onClicked: Screenshots.stepPreview(1)
                        }
                    }


                }

                Behavior on scale {
                    Anim {}
                }
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    RecordingDeleteModal {
        props: root.props
        deformMatrix: root.deformMatrix
    }

    ScreenshotDeleteModal {
        props: root.props
        deformMatrix: root.deformMatrix
    }
}
