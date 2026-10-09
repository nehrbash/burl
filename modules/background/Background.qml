pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Burl.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar

Variants {
    model: Screens.screens.filter(s => GlobalConfig.forScreen(s.name).background.enabled)

    StyledWindow {
        id: win

        required property ShellScreen modelData

        // Video wallpaper active on *this* screen? Gated on the mpvpaper child
        // process actually running (not just configured), so a crash or a
        // manual kill brings the still back on its own; mpvpaper owns the
        // pixels while it runs, so burl must not paint over them.
        readonly property bool videoOnThisScreen: Wallpapers.videoActiveFor(modelData.name)
        // background.video.enabled is a per-monitor opt-out, but one mpvpaper
        // process serves the whole background.video.output target and can't
        // exempt a single screen. So an opted-out screen while the daemon
        // paints elsewhere can't go transparent (nothing else would draw) or
        // claim the *background* layer (mpvpaper is already there — two
        // clients on one wlr layer is undefined stacking); it sits on
        // *bottom* instead, fully opaque, covering the video with the still.
        readonly property bool videoWallpaper: contentItem.Config.background.video.enabled && videoOnThisScreen
        readonly property bool optedOutOfVideo: !contentItem.Config.background.video.enabled && videoOnThisScreen
        // Whether *we* are the thing drawing the wallpaper.
        readonly property bool paintsWallpaper: contentItem.Config.background.wallpaperEnabled && !videoWallpaper

        screen: modelData
        name: "background"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        // mpvpaper runs on the wlr *background* layer (services/Wallpapers.qml,
        // `-l background`); two clients on one wlr layer is undefined
        // stacking, so whenever mpvpaper owns this screen's pixels this
        // window moves up to *bottom* instead — above the video, below every
        // real window. Opted in, it stays fully transparent so the trunk,
        // visualiser and desktop clock still draw over the video; opted out,
        // it goes fully opaque to hide the video under the still.
        WlrLayershell.layer: (paintsWallpaper && !optedOutOfVideo) ? WlrLayer.Background : WlrLayer.Bottom
        // Opaque black whenever not deferring to mpvpaper's own pixels — this
        // is what makes the video invisible (the end-4/dots-hyprland gotcha):
        // intentional in the opt-out case, a bug everywhere else.
        // surfaceFormat.opaque stays false so alpha survives when transparent.
        color: videoWallpaper ? "transparent" : "black"
        surfaceFormat.opaque: false

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        ShellState.ComponentRef {
            screen: win.screen
            slot: "background"
            component: win
        }

        Item {
            id: behindClock

            anchors.fill: parent

            Loader {
                id: wallpaper

                asynchronous: true

                anchors.fill: parent
                // The still-image path is untouched -- it just stands down
                // while a video is playing on this screen.
                active: win.paintsWallpaper

                sourceComponent: Wallpaper {}
            }

            Visualiser {
                anchors.fill: parent
                screen: win.modelData
                wallpaper: wallpaper
            }
        }

        SidebarTrunk {
            bar: ShellState.componentsFor(win.screen)?.bar ?? null
            height: parent.height
        }

        Loader {
            id: clockLoader

            asynchronous: true
            active: Config.background.desktopClock.enabled

            anchors.margins: Tokens.padding.extraLargeIncreased
            anchors.leftMargin: Tokens.padding.extraLargeIncreased + Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness)

            state: Config.background.desktopClock.position
            states: [
                State {
                    name: "top-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "top-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "top-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "middle-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "middle-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "bottom-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "bottom-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "bottom-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                    }
                }
            ]

            transitions: Transition {
                AnchorAnim {}
            }

            sourceComponent: DesktopClock {
                wallpaper: behindClock
                absX: clockLoader.x
                absY: clockLoader.y
            }
        }
    }
}
