.pragma library

var common = {
    "animations:enabled": 0,
    "general:gaps_in": 0,
    "general:gaps_out": 0,
    "decoration:rounding": 0,
    "decoration:active_opacity": 1,
    "decoration:inactive_opacity": 1
};
var performance = {
    "decoration:shadow:enabled": 0,
    "decoration:blur:enabled": 0,
    "general:border_size": 1,
    "general:allow_tearing": 1
};

function initialState() {
    return { focus: false, performance: false, applied: {}, pending: false, reloadObserved: false };
}

function options(state) {
    return Object.assign({}, state.focus || state.performance ? common : {}, state.performance ? performance : {});
}

function equal(left, right) {
    return JSON.stringify(left) === JSON.stringify(right);
}

function result(state, apply, reload) {
    return { state: state, options: apply ? options(state) : null, reload: !!reload };
}

function request(previous, mode, enabled) {
    if (mode !== "focus" && mode !== "performance")
        throw new Error("Unknown compositor effect mode: " + mode);
    var state = Object.assign({}, previous);
    state[mode] = enabled;
    if (state.pending)
        return result(state, false, false);
    var desired = options(state);
    if (Object.keys(state.applied).some(key => !(key in desired))) {
        state.pending = true;
        state.reloadObserved = false;
        return result(state, false, true);
    }
    var changed = !equal(state.applied, desired);
    state.applied = desired;
    return result(state, changed, false);
}

function reloaded(previous) {
    var state = Object.assign({}, previous);
    state.applied = options(state);
    state.reloadObserved = state.pending;
    return result(state, true, false);
}

function finished(previous, success) {
    var state = Object.assign({}, previous);
    state.pending = false;
    if (!success)
        return result(state, false, false);
    var apply = !state.reloadObserved || !equal(state.applied, options(state));
    state.applied = options(state);
    return result(state, apply, false);
}

function commands(options) {
    return Object.keys(options).map(key => {
        var parts = key.split(":");
        return "eval hl.config({ " + parts.join(" = { ") + " = " + options[key]
            + " }".repeat(parts.length - 1) + " })";
    });
}
