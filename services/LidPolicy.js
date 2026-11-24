const ACTIONS = ["sleep", "lock", "screenOff", "nothing"];
const INTERNAL_PANEL = /^(eDP|LVDS|DSI)/i;

function action(name, fallback) {
    return ACTIONS.includes(name) ? name : fallback;
}

function docked(monitorNames) {
    return (monitorNames ?? []).some(name => !INTERNAL_PANEL.test(name));
}

// Docked wins over power source, matching logind's HandleLidSwitchDocked.
function actionFor(lid, context) {
    if (context.docked)
        return action(lid.actionDocked, "nothing");
    return context.onBattery ? action(lid.action, "sleep") : action(lid.actionOnPower, "sleep");
}

// Steps are IdleMonitors.handleIdleAction inputs; sleepAction must already be normalised.
function closeSteps(name, idle) {
    switch (name) {
    case "sleep":
        return idle.lockBeforeSleep ? ["lock", [idle.sleepAction]] : [[idle.sleepAction]];
    case "lock":
        return ["lock"];
    case "screenOff":
        return ["dpms off"];
    default:
        return [];
    }
}

function openSteps(performed) {
    return performed === "screenOff" ? ["dpms on"] : [];
}
