import QtQuick
import Quickshell
import Burl.Config

ShellRoot {
    id: root
    settings.watchFiles: false

    Item {
        id: ordinary
        property bool observed: SurfaceContext.folio
    }
    Item {
        id: folio
        SurfaceContext.folio: true
        Item {
            id: nested
            property bool observed: SurfaceContext.folio
            Item { id: descendant; property bool observed: SurfaceContext.folio }
        }
        Loader {
            id: loaded
            asynchronous: true
            sourceComponent: Item { property bool observed: SurfaceContext.folio }
            onLoaded: Qt.callLater(root.run)
        }
    }
    Item { id: detached; property bool observed: SurfaceContext.folio }

    function check(condition, message) {
        if (!condition) throw new Error(message);
    }
    function run() {
        try {
            check(!ordinary.observed && folio.SurfaceContext.folio, "independent roots");
            check(nested.observed && descendant.observed && loaded.item.observed, "nested and Loader inheritance");
            nested.SurfaceContext.folio = false;
            check(!nested.observed && !descendant.observed, "explicit false overrides folio parent");
            folio.SurfaceContext.folio = false;
            folio.SurfaceContext.folio = true;
            check(!nested.observed && !descendant.observed, "parent changes preserve explicit false");
            nested.SurfaceContext.folio = undefined;
            check(nested.observed && descendant.observed, "reset resumes inheritance");
            nested.parent = ordinary;
            check(!nested.observed && !descendant.observed, "reparent to ordinary resets descendants");
            nested.parent = folio;
            check(nested.observed && descendant.observed, "reparent to folio inherits");
            nested.parent = null;
            check(!nested.observed && !descendant.observed, "no-context parent resets false");
            loaded.item.parent = ordinary;
            check(!loaded.item.observed, "loaded item reparent follows visual parent");
            detached.SurfaceContext.folio = true;
            detached.parent = ordinary;
            check(detached.observed && !ordinary.observed, "explicit true survives reparent without changing root");
            detached.SurfaceContext.resetFolio();
            check(!detached.observed, "method reset resumes ordinary context");
            console.log("SURFACE-CONTEXT-PASS");
        } catch (error) {
            console.error("SURFACE-CONTEXT-FAIL", error.message);
        }
        Qt.quit();
    }
}
