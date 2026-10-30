pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Burl
import Burl.Config
import qs.services

Singleton {
    id: root

    // Create the owner before PersistentProperties restores the reload graph.
    readonly property var compositorEffects: CompositorEffects

    readonly property bool enabled: PowerProfiles.profile === PowerProfile.Performance
    readonly property bool available: PowerProfiles.hasPerformanceProfile
    property bool ready: false
    readonly property bool pauseAnimations: enabled && GlobalConfig.performance.pauseAnimations !== false
    readonly property bool releaseScenes: enabled && GlobalConfig.performance.releaseScenes !== false
    readonly property bool disableBlur: enabled && GlobalConfig.performance.blur !== false
    readonly property bool llamaAvailable: Quickshell.env("BURL_MANAGE_LLAMA") === "1"
    readonly property bool manageLlama: enabled && GlobalConfig.performance.stopLlama !== false
    readonly property var plugins: HyprlandPlugins

    function setProfile(profile: int): void {
        if (profile !== PowerProfile.Performance || available)
            PowerProfiles.profile = profile;
    }

    function setEnabled(on: bool): void {
        setProfile(on ? PowerProfile.Performance : PowerProfile.Balanced);
    }

    function toggle(): void {
        setEnabled(!enabled);
    }

    function restoreLlama(): void {
        if (llamaAvailable && !manageLlama && props.llamaStopped) {
            props.llamaStopped = false;
            Quickshell.execDetached(["herd", "start", "llama-server"]);
        }
    }

    function syncEffects(): void {
        if (!ready)
            return;
        root.compositorEffects.setMode("performance", enabled);
        if (manageLlama) {
            if (llamaAvailable && !props.llamaStopped && !stopLlama.running)
                stopLlama.running = true;
        } else {
            restoreLlama();
        }
        if (enabled === props.effectsApplied)
            return;
        props.effectsApplied = enabled;
        if (GlobalConfig.utilities.toasts.gameModeChanged)
            Toaster.toast(enabled ? qsTr("Performance mode enabled") : qsTr("Performance mode disabled"),
                enabled ? qsTr("Your performance preferences are active") : qsTr("Desktop settings restored"), "rocket_launch");
    }

    function llamaStopped(text: string): void {
        props.llamaStopped = text.trim().split("\n").pop() === "#t";
        restoreLlama();
    }

    onEnabledChanged: syncEffects()
    onManageLlamaChanged: syncEffects()

    PersistentProperties {
        id: props

        property bool effectsApplied: false
        property bool llamaStopped: false

        reloadableId: "gameMode"
        onLoaded: {
            root.ready = true;
            root.syncEffects();
        }
    }

    Process {
        id: stopLlama

        // Only resume a service this mode found running and successfully stopped.
        command: ["herd", "eval", "root", "(let ((svc (lookup-service 'llama-server))) (and svc (service-running-value svc) (begin (stop-service svc) (not (service-running-value svc)))))"]
        stdout: StdioCollector {
            onStreamFinished: root.llamaStopped(text)
        }
    }

    IpcHandler {
        function isEnabled(): bool {
            return root.enabled;
        }

        function toggle(): void {
            root.toggle();
        }

        function enable(): void {
            root.setEnabled(true);
        }

        function disable(): void {
            root.setEnabled(false);
        }

        target: "gameMode"
    }
}
