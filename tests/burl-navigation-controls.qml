import QtQuick
import Quickshell
import Quickshell.Io
import qs.components.controls

ShellRoot {
    id: root
    property int selection: 0

    FloatingWindow {
        id: window
        title: "Burl navigation control test"
        visible: true
        implicitWidth: 240
        implicitHeight: 100

        NavigationTabs {
            id: tabs
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            model: [{text: "Network"}, {text: "Calendar"}, {text: "Today"}, {text: "This week"}]
            currentIndex: root.selection
            onActivated: index => root.selection = index
        }
    }

    IpcHandler {
        target: "navigationControls"
        function ready(): bool { return tabs.count === 4 && window.visible; }
        function focus(): void { tabs.itemAt(root.selection).forceActiveFocus(); }
        function state(): string {
            const item = tabs.currentItem;
            const x = item.mapToItem(tabs, 0, 0).x;
            let checked = 0;
            for (let i = 0; i < tabs.count; i++) if (tabs.itemAt(i).checked) checked++;
            return JSON.stringify({index: root.selection, checked: checked, focused: item.activeFocus,
                visible: x >= -1 && x + item.width <= tabs.width + 1});
        }
        function replace(): void {
            tabs.model = [{text: "One"}, {text: "Two"}, {text: "Three"}, {text: "Four"}];
        }
    }
}
