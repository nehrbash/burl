import QtQuick
import Quickshell
import Quickshell.Io
import Burl.Config
import qs.components
import qs.modules.launcher

ShellRoot {
    id: root
    settings.watchFiles: false
    property bool coldPending: false
    property bool editorPending: false

    ScreenState {
        id: navigation
        modelData: Quickshell.screens[0]
    }

    function sceneLoader() {
        return surface.children.find(child => child.asynchronous !== undefined && child.sourceComponent !== undefined);
    }

    FloatingWindow {
        implicitWidth: 1280
        implicitHeight: 720
        visible: true

        Item {
            anchors.fill: parent
            Config.screen: navigation.modelData.name
            Wrapper {
                id: surface
                screen: navigation.modelData
                visibilities: navigation
                panels: ({})
                onShouldBeActiveChanged: {
                    if (shouldBeActive)
                        return;
                    if (root.coldPending) {
                        console.log(root.sceneLoader().item === null ? "WORLD-ESCAPE-COLD-PASS" : "WORLD-ESCAPE-FAIL", "cold close");
                        root.coldPending = false;
                    }
                    if (root.editorPending) {
                        console.log(editor.activeFocus ? "WORLD-ESCAPE-EDITOR-PASS" : "WORLD-ESCAPE-FAIL", "editor close");
                        root.editorPending = false;
                    }
                }
            }
            TextInput {
                id: editor
                width: 200
                height: 40
                z: 10
                visible: root.editorPending
                text: "fixture editor"
            }
        }
    }

    IpcHandler {
        target: "worldEscape"
        function armCold(): string {
            if (root.sceneLoader().item !== null)
                return "already loaded";
            root.coldPending = true;
            navigation.openRoom("dashboard", "key");
            return "armed";
        }
        function armPlaylist(): void {
            navigation.openRoom("launcher", "key");
        }
        function playlistReady(): bool {
            return (root.sceneLoader().item?.revealP ?? 0) > 0.99 && root.sceneLoader().item.atSky;
        }
        function openPlaylist(): bool {
            const content = root.sceneLoader().item;
            content.openPlaylist({uri: "fixture", name: "Fixture playlist"});
            content.playlistReturn = {query: ">spotify", selection: null};
            return content.openedPlaylist !== null;
        }
        function playlistReturned(): bool {
            const content = root.sceneLoader().item;
            return navigation.launcher && content.openedPlaylist === null
                && content.scope?.length === 2 && content.scope[0].kind === "spotifyPlaylist";
        }
        function worldClosed(): bool { return !navigation.worldOpen; }
        function armEditor(): void {
            root.editorPending = true;
            navigation.openRoom("dashboard", "key");
        }
        function editorReady(): bool {
            return (root.sceneLoader().item?.revealP ?? 0) > 0.99;
        }
        function focusEditor(): bool {
            editor.forceActiveFocus();
            return editor.activeFocus;
        }
    }

    Component.onCompleted: console.log("WORLD-ESCAPE-READY")
}
