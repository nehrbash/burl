pragma ComponentBehavior: Bound

import QtQuick
import Burl.Config
import qs.components
import qs.services
import "NodePreview.js" as Preview

Rectangle {
    id: root

    property var node: null
    property bool actionsAvailable: false
    property bool primaryAvailable: true
    property bool emacsEnabled: true
    readonly property var descriptor: Preview.describe(node, {
        actionsAvailable: root.actionsAvailable,
        primaryAvailable: root.primaryAvailable,
        emacsEnabled: root.emacsEnabled
    })

    implicitWidth: 300
    implicitHeight: content.implicitHeight + Tokens.spacing.medium * 2
    radius: Tokens.spacing.medium
    color: Woodland.velvet
    border.color: Colours.palette.m3primary
    border.width: 1

    Column {
        id: content

        x: Tokens.spacing.medium
        y: Tokens.spacing.medium
        width: Math.max(0, root.width - Tokens.spacing.medium * 2)
        spacing: Tokens.spacing.small

        StyledText {
            width: parent.width
            visible: text.length > 0
            text: root.descriptor.kind
            color: Colours.palette.m3primary
            font: Tokens.font.body.small
            elide: Text.ElideRight
        }

        StyledText {
            width: parent.width
            text: root.descriptor.title
            color: Woodland.parchment
            font.pointSize: Tokens.font.body.large.pointSize
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Repeater {
            model: root.descriptor.details

            StyledText {
                required property string modelData

                width: content.width
                text: modelData
                color: Qt.alpha(Woodland.parchment, 0.78)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideMiddle
            }
        }

        StyledText {
            width: parent.width
            visible: text.length > 0
            text: root.descriptor.hint
            color: Qt.alpha(Woodland.parchment, 0.78)
            wrapMode: Text.WordWrap
        }
    }
}
