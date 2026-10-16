pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "CompositorEffectPolicy.js" as Policy

Singleton {
    id: root

    property var state: Policy.initialState()
    property bool ready: false
    property var queued: ({})
    property bool timedOut: false

    function execute(change: var): void {
        state = change.state;
        props.focus = state.focus;
        props.performance = state.performance;
        props.appliedCommon = Object.keys(state.applied).length > 0;
        props.appliedPerformance = "general:allow_tearing" in state.applied;
        if (change.options !== null)
            Hypr.extras.batchMessage(Policy.commands(change.options));
        if (change.reload) {
            timedOut = false;
            reload.running = true;
            deadline.restart();
        }
    }

    function setMode(mode: string, enabled: bool): void {
        if (!ready) {
            queued[mode] = enabled;
            return;
        }
        execute(Policy.request(state, mode, enabled));
    }

    PersistentProperties {
        id: props
        reloadableId: "compositorEffects"
        // JS objects cannot cross Quickshell reload engines.
        property bool focus: false
        property bool performance: false
        property bool appliedCommon: false
        property bool appliedPerformance: false

        onLoaded: {
            root.state = {
                focus: focus, performance: performance,
                applied: Policy.options({ focus: appliedCommon, performance: appliedPerformance }),
                pending: false, reloadObserved: false
            };
            root.ready = true;
            Hypr.extras.batchMessage(Policy.commands(Policy.options(root.state)));
            root.execute(Policy.request(root.state, "focus", focus));
            for (const mode of Object.keys(root.queued))
                root.setMode(mode, root.queued[mode]);
            root.queued = {};
        }
    }

    Process {
        id: reload
        command: ["hyprctl", "reload"]
        onExited: (exitCode, exitStatus) => {
            deadline.stop();
            const success = exitCode === 0 && exitStatus === 0 && !root.timedOut;
            root.execute(Policy.finished(root.state, success));
            if (!success)
                console.warn("Compositor effects: config reload failed; restoration will retry on the next mode request");
        }
    }

    Timer {
        id: deadline
        interval: 3000
        onTriggered: {
            root.timedOut = true;
            if (reload.running)
                reload.signal(9);
            else
                root.execute(Policy.finished(root.state, false));
            console.warn("Compositor effects: config reload timed out");
        }
    }

    Connections {
        target: Hypr
        function onConfigReloaded(): void {
            if (root.ready)
                root.execute(Policy.reloaded(root.state));
        }
    }
}
