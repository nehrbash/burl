import QtQuick
import Quickshell
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.widgets
import qs.modules.dashboard

Item {
    id: root
    Config.screen: Quickshell.screens[0].name
    Tokens.screen: Quickshell.screens[0].name

    StyledText { id: ordinaryText; x: 30; y: 40; text: "Ordinary shell text" }
    BarkCard { id: ordinaryCard; x: 30; y: 90; width: 270; height: 120 }
    CircularProgress { id: ordinaryProgress; x: 100; y: 230; width: 100; height: 100; value: 0.65 }

    Grimoire {
        id: book
        x: 340
        width: root.width - x
        height: root.height
        title: "Tasks"
        coverId: "tasks"
        opening: 1
        TasksTab { id: tasks; anchors.fill: parent }
    }

    function check(condition, message) {
        if (!condition) throw new Error(message);
    }
    function texts(item, result) {
        if (item.folio !== undefined && item.renderType !== undefined)
            result.push(item);
        for (const child of item.children ?? []) texts(child, result);
        return result;
    }
    Timer {
        interval: 3000
        running: true
        onTriggered: {
            try {
                root.check(!ordinaryText.folio && !ordinaryCard.folio && !ordinaryProgress.folio,
                           "ordinary controls retain shell style");
                root.check(tasks.folio, "task page inherits folio treatment");
                const labels = root.texts(tasks, []);
                root.check(labels.length > 5, "task page instantiated nested labels");
                root.check(labels.every(label => label.folio && label.renderType === Text.QtRendering),
                           "all nested task labels use folio distance-field rendering");
                console.log("SURFACE-CONTROLS-PASS");
            } catch (error) {
                console.error("SURFACE-CONTROLS-FAIL", error.message);
            }
        }
    }
}
