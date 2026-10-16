import QtQuick
import Quickshell
import Quickshell.Io
import Burl.Config
import qs.components
import qs.modules.launcher

ShellRoot {
    id: root
    settings.watchFiles: false
    property int sceneCount: 0
    property string expectedSelection: ""

    ScreenState { id: navigation; modelData: Quickshell.screens[0] }

    function loader() {
        return surface.children.find(child => child.asynchronous !== undefined && child.sourceComponent !== undefined);
    }
    function findChild(item, predicate) {
        if (!item) return null;
        if (predicate(item)) return item;
        for (const child of item.children ?? []) {
            const found = findChild(child, predicate);
            if (found) return found;
        }
        return null;
    }
    function search() { return findChild(loader().item, item => item.objectName === "launcherSearch"); }
    function graph() { return findChild(loader().item, item => item.nodes !== undefined && item.selectNode !== undefined); }

    Connections {
        target: root.loader() ?? null
        function onItemChanged() { if (root.loader().item) root.sceneCount++; }
    }

    FloatingWindow {
        implicitWidth: 1280
        implicitHeight: 720
        visible: true
        Item {
            anchors.fill: parent
            Config.screen: navigation.modelData.name
            Wrapper { id: surface; screen: navigation.modelData; visibilities: navigation; panels: ({}) }
        }
    }

    IpcHandler {
        target: "launcherEditing"
        function open(): void { navigation.openRoom("launcher", "key"); }
        function ready(): bool {
            return navigation.worldOpen && root.loader().item?.atSky === true
                && root.loader().item.revealP > 0.99 && root.search() !== null;
        }
        function seed(text: string, cursor: int): bool {
            const field = root.search();
            field.text = text;
            field.cursorPosition = cursor;
            field.forceActiveFocus();
            return field.activeFocus;
        }
        function state(): string {
            const field = root.search();
            const graph = root.graph();
            const content = root.loader().item;
            return JSON.stringify({text: field?.text, cursor: field?.cursorPosition,
                focused: field?.activeFocus, selected: graph?.nodes[graph.currentNode]?.id ?? "",
                playlist: content?.openedPlaylist?.uri ?? "", returnQuery: content?.playlistReturn?.query ?? "",
                scenes: root.sceneCount, closed: !navigation.worldOpen});
        }
        function playlist(): void {
            root.search().text = ">spotify original";
            root.loader().item.openPlaylist({uri: "fixture", name: "Fixture playlist"});
            root.search().text = "Fixture";
            root.graph().flushSearch();
            root.graph().selectNode(root.graph().indexById["spotify:pl:fixture"]);
        }
        function close(): void { navigation.closeWorld("fixture"); }
        function selectSecondApplication(): bool {
            if (root.loader().item.openedPlaylist) root.loader().item.leavePlaylist();
            root.search().text = "";
            const graph = root.graph();
            graph.rebuild();
            graph.flushSearch();
            const apps = graph.nodes.filter(node => node.kind === "app");
            if (apps.length < 2) return false;
            root.expectedSelection = apps[1].id;
            const index = graph.indexById[root.expectedSelection];
            if (index === 0) return false;
            graph.selectNode(index);
            return graph.currentNode === index;
        }
        function selectionRetained(): bool {
            const graph = root.graph();
            return root.expectedSelection !== "" && graph?.nodes[graph.currentNode]?.id === root.expectedSelection;
        }
        function hidden(): bool { return !surface.visible; }
        function destroyScene(): bool {
            if (navigation.worldOpen || surface.visible) return false;
            root.loader().active = false;
            return root.loader().item === null;
        }
        function recreate(): void {
            root.loader().active = true;
            navigation.openRoom("launcher", "key");
        }
    }
    Component.onCompleted: console.log("LAUNCHER-EDITING-READY")
}
