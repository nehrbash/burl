pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services

Item {
    id: root

    property real opening: 1
    property bool preparing: opening > 0
    property string title: ""
    property string coverId: "dashboard"
    readonly property string assetDirectory: "assets/images/book/" + (["media", "performance", "weather", "tasks"].includes(coverId) ? coverId + "/" : "")
    property color accent: Colours.palette.m3primary
    readonly property bool bookSurface: true
    readonly property real reserveWidth: 0.18
    readonly property real spine: width * reserveWidth
    readonly property real pageWidth: width - spine
    readonly property real pageAspect: (720 * 0.644657969) / (500 * 0.623445168)
    readonly property real fittedHeight: Math.min(height, pageWidth / pageAspect)
    readonly property real fittedWidth: fittedHeight * pageAspect
    readonly property real pageLeft: spine + (pageWidth - fittedWidth) / 2
    readonly property real pageTop: (height - fittedHeight) / 2
    readonly property int coverFrame: Math.round(Math.max(0, Math.min(1, opening)) * 24)
    readonly property int renderedFrames: book.frameCount
    readonly property bool renderReady: finalPage.status === Image.Ready
    default property alias content: contentHost.data

    signal closeRequested()

    AnimatedSprite {
        id: book
        x: root.pageLeft - width * 0.262282372
        y: root.pageTop - height * 0.187282503
        width: root.fittedWidth / 0.644657969
        height: width * 500 / 720
        source: root.preparing ? Quickshell.shellPath(root.assetDirectory + "opening-sheet.png") : ""
        visible: root.coverFrame !== 24
        running: false
        interpolate: false
        frameWidth: 720
        frameHeight: 500
        frameCount: 25
        currentFrame: root.coverFrame

        smooth: true
    }

    Image {
        id: finalPage
        x: book.x; y: book.y
        width: book.width; height: book.height
        source: root.preparing ? Quickshell.shellPath(root.assetDirectory + "book-25.png") : ""
        visible: root.coverFrame === 24
        mipmap: true
    }

    MouseArea {
        x: book.x
        y: book.y
        width: Math.max(0, root.pageLeft - x)
        height: book.height
        enabled: root.opening > 0.95
    }

    Item {
        x: root.pageLeft
        y: root.pageTop
        width: root.fittedWidth
        height: root.fittedHeight
        opacity: Math.max(0, Math.min(1, (root.opening - 0.94) / 0.06))
        enabled: root.opening > 0.98

        CelestialSeal {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            width: Math.min(parent.width, parent.height) * 0.55
            height: width
            ink: root.accent
            opacity: 0.08
            enabled: false
        }
        Text {
            x: 8; y: 78
            width: 14
            text: "⋔\n⟐\n⋈\nϟ\n⊹\n⋔\n⟐\n⋈"
            font.pixelSize: 11
            lineHeight: 1.8
            color: Qt.alpha(root.accent, 0.38)
        }

        Text {
            x: 34; y: 22
            text: root.title.toUpperCase()
            font.family: "serif"
            font.pixelSize: 14
            font.letterSpacing: 3
            color: root.accent
        }
        Rectangle {
            x: 34; y: 48
            width: parent.width - 68; height: 1
            color: Qt.alpha(root.accent, 0.3)
        }
        Item {
            id: contentHost
            x: 30; y: 66
            width: parent.width - 64
            height: parent.height - 94
        }
        Text {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 10
            text: "·  I  ·"
            color: Qt.alpha(root.accent, 0.48)
            font.family: "serif"
            font.pixelSize: 10
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 26
            y: -5; width: 26; height: 39
            color: closeArea.containsMouse ? root.accent : Woodland.mix(Woodland.barkEdge, root.accent, 0.45)
            Text {
                anchors.centerIn: parent
                text: "×"
                color: Woodland.parchment
                font.pixelSize: 20
            }
            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested()
            }
        }
    }
}
