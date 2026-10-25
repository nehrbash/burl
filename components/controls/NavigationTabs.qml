pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    property var model: []
    property int currentIndex: 0
    readonly property alias count: entries.count
    readonly property var currentItem: { entries.count; return entries.itemAt(currentIndex); }

    function itemAt(index: int): var { return entries.itemAt(index); }
    signal activated(index: int)

    function select(index: int): void {
        if (!count) return;
        const target = (index + count) % count;
        activated(target);
        Qt.callLater(() => itemAt(target)?.forceActiveFocus());
    }

    function revealCurrent(): void {
        const item = currentItem;
        if (!item) return;
        const left = row.x + item.x;
        const right = left + item.width;
        if (left < viewport.contentX) viewport.contentX = left;
        else if (right > viewport.contentX + viewport.width) viewport.contentX = right - viewport.width;
        viewport.returnToBounds();
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    onCurrentIndexChanged: Qt.callLater(revealCurrent)
    onModelChanged: Qt.callLater(revealCurrent)
    onWidthChanged: Qt.callLater(revealCurrent)

    Flickable {
        id: viewport
        anchors.fill: parent
        contentWidth: Math.max(width, row.implicitWidth)
        contentHeight: row.implicitHeight
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Row {
            id: row
            x: Math.max(0, (viewport.width - implicitWidth) / 2)
            Repeater {
                id: entries
                model: root.model
                delegate: NavigationTab {
                    required property var modelData
                    required property int index

                    text: modelData.text
                    iconName: modelData.iconName || ""
                    checked: index === root.currentIndex
                    onClicked: root.activated(index)
                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Left: root.select(index - 1); break;
                        case Qt.Key_Right: root.select(index + 1); break;
                        case Qt.Key_Home: root.select(0); break;
                        case Qt.Key_End: root.select(root.count - 1); break;
                        default: return;
                        }
                        event.accepted = true;
                    }
                }
            }
        }
    }

}
