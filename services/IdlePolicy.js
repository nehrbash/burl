const SLEEP_ACTIONS = ["suspend", "suspendThenHibernate", "hibernate"];

function seconds(value) {
    const n = Number(value);
    return Number.isFinite(n) && n > 0 ? Math.round(n) : 0;
}

function sleepAction(name) {
    return SLEEP_ACTIONS.includes(name) ? name : "suspend";
}

// A non-empty raw `timeouts` list wins so configs written for the old schema keep their behaviour.
function monitors(idle) {
    if (idle.timeouts && idle.timeouts.length > 0)
        return idle.timeouts;

    const stages = [];
    const lock = seconds(idle.lockAfter);
    const screenOff = seconds(idle.screenOffAfter);
    const sleep = seconds(idle.sleepAfter);
    if (lock)
        stages.push({ timeout: lock, idleAction: "lock" });
    if (screenOff)
        stages.push({ timeout: screenOff, idleAction: "dpms off", returnAction: "dpms on" });
    if (sleep)
        stages.push({ timeout: sleep, idleAction: [sleepAction(idle.sleepAction)] });
    return stages;
}

function usesLegacyTimeouts(idle) {
    return !!idle.timeouts && idle.timeouts.length > 0;
}
