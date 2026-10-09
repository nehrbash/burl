pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Burl.Components
import Burl.Config
import Burl.Models
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Wallpapers")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.small

        ButtonRow {
            Layout.bottomMargin: Tokens.spacing.medium
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "photo_library"
                text: qsTr("Browse")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: browseDialog.open()

                FileDialog {
                    id: browseDialog

                    title: qsTr("Select an image")
                    filterLabel: qsTr("Image files")
                    filters: Images.validImageExtensions
                    onAccepted: path => {
                        Wallpapers.setWallpaper(path);
                        root.nState.closeSubPage();
                    }
                }
            }

            IconTextButton {
                icon: "shuffle"
                text: qsTr("Random")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                type: IconTextButton.Tonal
                onClicked: {
                    Wallpapers.setRandom();
                    root.nState.closeSubPage();
                }
            }
        }

        WallItem {
            imgHeight: Math.round(width * 0.3)
            radius: Tokens.rounding.extraLarge
            source: Quickshell.shellPath("assets/images/ui/wallpaper.webp")
            text: qsTr("Featured wallpaper")
            fillLabel: false
            onClicked: {
                Wallpapers.setWallpaper(Quickshell.shellPath("assets/images/ui/wallpaper.webp"));
                root.nState.closeSubPage();
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.large
            text: qsTr("Local wallpapers")
            font: Tokens.font.title.small
        }

        GridLayout {
            Layout.fillWidth: true
            visible: localWalls.count > 0

            columns: Config.nexus.wallpapersPerRow
            rowSpacing: Tokens.spacing.medium
            columnSpacing: Tokens.spacing.large

            Repeater {
                id: localWalls

                model: {
                    const walls = Wallpapers.list;
                    const baseDir = Paths.wallsdir;
                    const categories = {};
                    const list = [];
                    for (const w of walls) {
                        if (w.parentDir !== baseDir) {
                            const category = Wallpapers.getCategoryFor(w);
                            if (category && (!(category in categories) || categories[category].name.localeCompare(w.name) > 0))
                                categories[category] = w;
                        } else {
                            list.push(w);
                        }
                    }
                    list.push(...Object.values(categories));
                    list.sort((a, b) => ((a.parentDir === baseDir) - (b.parentDir === baseDir)) || a.name.localeCompare(b.name));
                    if (list.length === 0)
                        return [];
                    while (list.length < Config.nexus.wallpapersPerRow)
                        list.push(null);
                    return list;
                }

                WallItem {
                    required property FileSystemEntry modelData

                    // Empty placeholders for sizing
                    opacity: modelData ? 1 : 0
                    enabled: modelData

                    source: String(modelData?.path ?? "")
                    text: {
                        if (!modelData)
                            return "";

                        if (modelData.parentDir !== Paths.wallsdir) {
                            const category = Wallpapers.getCategoryFor(modelData);
                            return category.slice(0, 1).toUpperCase() + category.slice(1);
                        }
                        return modelData.name;
                    }
                    onClicked: {
                        if (modelData.parentDir !== Paths.wallsdir) {
                            root.nState.selectedWallpaperCategory = Wallpapers.getCategoryFor(modelData);
                            root.nState.openSubPage(2); // Category page
                        } else {
                            Wallpapers.setWallpaper(modelData.path);
                            root.nState.closeSubPage();
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.large
            text: qsTr("Live wallpapers")
            font: Tokens.font.title.small
        }

        GridLayout {
            Layout.fillWidth: true
            visible: liveWalls.count > 0

            columns: Config.nexus.wallpapersPerRow
            rowSpacing: Tokens.spacing.medium
            columnSpacing: Tokens.spacing.large

            Repeater {
                id: liveWalls

                model: {
                    const vids = [...Wallpapers.videoList].sort((a, b) => a.name.localeCompare(b.name));
                    if (vids.length === 0)
                        return [];
                    while (vids.length < Config.nexus.wallpapersPerRow)
                        vids.push(null);
                    return vids;
                }

                VideoWallItem {
                    required property FileSystemEntry modelData

                    // Empty placeholders for sizing
                    opacity: modelData ? 1 : 0
                    enabled: modelData

                    videoPath: String(modelData?.path ?? "")
                    text: modelData?.name ?? ""
                    onClicked: {
                        Wallpapers.setVideoWallpaper(modelData.path);
                        root.nState.closeSubPage();
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true

            asynchronous: true
            active: liveWalls.count === 0
            visible: active

            sourceComponent: StyledRect {
                color: Colours.tPalette.m3surfaceContainer
                radius: Tokens.rounding.extraLarge
                implicitHeight: noVideosLayout.implicitHeight + Tokens.padding.extraExtraLarge * 2

                ColumnLayout {
                    id: noVideosLayout

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "movie_off"
                        color: Woodland.creamSecondary
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("No videos in %1").arg(Paths.shortenHome(Paths.videowallsdir))
                        color: Woodland.creamSecondary
                        font: Tokens.font.title.small
                    }
                }
            }
        }

        ButtonRow {
            Layout.topMargin: Tokens.spacing.medium
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "video_library"
                text: qsTr("Browse videos")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: videoDialog.open()

                FileDialog {
                    id: videoDialog

                    title: qsTr("Select a video")
                    filterLabel: qsTr("Video files")
                    filters: ["mp4", "webm", "mkv", "mov", "avi"]
                    onAccepted: path => {
                        Wallpapers.setVideoWallpaper(path);
                        root.nState.closeSubPage();
                    }
                }
            }

            IconTextButton {
                icon: "stop_circle"
                text: qsTr("Stop")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                disabled: !Wallpapers.videoActive
                onClicked: Wallpapers.clearVideoWallpaper()
            }
        }

        SliderRow {
            Layout.topMargin: Tokens.spacing.medium

            first: true
            last: true
            visible: Wallpapers.videoActive
            icon: "speed"
            label: qsTr("Playback speed")
            valueLabel: `${Wallpapers.videoSpeed.toFixed(2)}x`
            // 0.25x .. 2x mapped onto the slider's 0..1.
            value: (Wallpapers.videoSpeed - 0.25) / 1.75
            onMoved: v => GlobalConfig.background.video.speed = 0.25 + v * 1.75
        }

        Loader {
            Layout.fillWidth: true

            asynchronous: true
            active: localWalls.count === 0
            visible: active

            sourceComponent: StyledRect {
                color: Colours.tPalette.m3surfaceContainer
                radius: Tokens.rounding.extraLarge
                implicitHeight: noWallsLayout.implicitHeight + Tokens.padding.extraExtraLarge * 2

                ColumnLayout {
                    id: noWallsLayout

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Woodland.creamSecondary
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("No local wallpapers found")
                        color: Woodland.creamSecondary
                        font: Tokens.font.title.small
                    }
                }
            }
        }
    }
}
