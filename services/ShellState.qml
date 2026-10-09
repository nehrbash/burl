pragma Singleton

import QtQuick
import Quickshell
import Burl
import qs.components
import qs.services

Singleton {
    property ShellRoot shellRoot

    // Set by the `launcher` IPC just before raising the launcher flag; the
    // launcher's search field claims it on open. A property rather than a
    // signal because the field may not be mounted yet when the IPC lands.
    property string pendingLauncherQuery

    function anySidebarOpen(): bool {
        return states.instances.some(s => s.sidebar);
    }

    function setBarAll(v: bool): void {
        for (const s of states.instances)
            s.bar = v;
    }

    function selectWorkspace(requests: var): void {
        for (const state of states.instances) {
            state.launcher = false;
            state.dashboard = false;
        }
        if (requests.length > 0)
            Hypr.batchDispatch(requests);
    }

    function forScreen(screen: ShellScreen): ScreenState {
        for (const s of states.instances)
            if (s.modelData === screen)
                return s;
        return null;
    }

    function forActive(): ScreenState {
        const mon = Hypr.focusedMonitor;
        for (const s of states.instances)
            if (Hypr.monitorFor(s.modelData) === mon)
                return s;
        // No focused-monitor match (e.g. mid monitor hotplug) — fall back to
        // the first screen rather than returning null.
        return states.instances[0] ?? null;
    }

    function componentsFor(screen: ShellScreen): Components {
        for (const c of components.instances)
            if (c.modelData === screen)
                return c;
        return null;
    }

    function componentsForActive(): Components {
        const mon = Hypr.focusedMonitor;
        for (const c of components.instances)
            if (Hypr.monitorFor(c.modelData) === mon)
                return c;
        return null;
    }

    Variants {
        id: states

        model: Screens.screens

        ScreenState {}
    }

    Variants {
        id: components

        model: Screens.screens

        Components {}
    }

    component Components: QtObject {
        required property ShellScreen modelData

        property var background
        property var rootWindow
        property var interactionWrapper
        property var bar
        property var panels

        function find(name: string, rootItem: Item): var {
            return CUtils.findChild(rootItem ?? rootWindow?.contentItem, name);
        }

        function findAll(name: string, rootItem: Item): var {
            return CUtils.findChildren(rootItem ?? rootWindow?.contentItem, name);
        }

        function findMatching(pattern: string, rootItem: Item): var {
            return CUtils.findChildrenMatching(rootItem ?? rootWindow?.contentItem, pattern);
        }
    }

    component ComponentRef: QtObject {
        required property ShellScreen screen
        required property string slot
        required property var component

        readonly property QtObject target: ShellState.componentsFor(screen)

        onTargetChanged: {
            if (target)
                target[slot] = component;
        }
        Component.onDestruction: {
            if (target && target[slot] === component)
                target[slot] = null;
        }
    }
}
