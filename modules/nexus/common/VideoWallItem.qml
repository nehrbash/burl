pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Burl.Config
import qs.components
import qs.services

WallItem {
    id: root

    required property string videoPath

    // The thumbnail is the palette frame itself, so the picker shows exactly
    // the still the scheme would be derived from. One ffmpeg pass per file,
    // cached by content hash after that.
    Process {
        running: root.videoPath !== ""
        command: ["burl-video-wallpaper", "-T", root.videoPath]
        stdout: StdioCollector {
            onStreamFinished: root.source = text.trim()
        }
    }

    MaterialIcon {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.padding.small

        text: Wallpapers.videoPath === root.videoPath ? "play_circle" : "movie"
        color: Colours.palette.m3onSurface
        fontStyle: Tokens.font.icon.medium
    }
}
