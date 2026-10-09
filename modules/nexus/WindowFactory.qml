pragma Singleton

import QtQuick
import Quickshell
import Burl.Config
import qs.components
import qs.services
import qs.modules.nexus

Singleton {
    id: root

    // Typed (not `var`) so QML nulls it automatically when the window is
    // destroyed by any route — a stale reference would mean settings could
    // never be opened again.
    property FloatingWindow current: null

    // Multiple entry points (IPC, keybind, quick toggle, pop-out button) each
    // used to instantiate their own window, so opening settings twice opened
    // two windows fighting over the same config; an already-open window is
    // focused instead. Focus by class, not address: nexus is the shell's only
    // real toplevel, so `class:org.quickshell` is unambiguous.
    //
    // Pass the `hl.…` form directly rather than branching on Hypr.usingLua:
    // usingLua reads FALSE on this host even though the config is Lua, so the
    // plain-Hyprland string ("focuswindow class:…") gets eval'd as Lua and
    // dies with "')' expected near 'class'". `hl.` strings pass through
    // untouched either way.
    function create(parent: Item, props: var): void {
        if (root.current) {
            Hypr.dispatch(`hl.dsp.focus({ window = "class:org.quickshell" })`);
            return;
        }
        root.current = nexusComp.createObject(parent ?? dummy, props);
    }

    QtObject {
        id: dummy
    }

    Component {
        id: nexusComp

        FloatingWindow {
            id: win

            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false

            onVisibleChanged: {
                if (!visible) {
                    if (root.current === win)
                        root.current = null;
                    destroy();
                }
            }

            implicitWidth: nexus.implicitWidth
            implicitHeight: nexus.implicitHeight

            minimumSize.width: contentItem.Tokens.sizes.nexus.minWidth
            minimumSize.height: contentItem.Tokens.sizes.nexus.minHeight

            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name

            title: qsTr("Nexus — %1").arg(PageRegistry.page(nexus.nState.currentPageId).label)

            Nexus {
                id: nexus

                anchors.fill: parent
                nState.screen: win.screen
                nState.isWindow: true
                onClose: {
                    if (root.current === win)
                        root.current = null;
                    win.destroy();
                }
            }

            Behavior on color {
                CAnim {}
            }
        }
    }
}
