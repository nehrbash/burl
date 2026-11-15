.pragma library

function manifest(text) {
    var paths = [];
    var pattern = /"([^"\n]+\.so)"/g;
    var match;
    while ((match = pattern.exec(text))) {
        var path = match[1];
        if (path.startsWith("/") && !path.includes("\\"))
            paths.push({ id: path.split("/").pop().slice(0, -3).toLowerCase(), path: path });
    }
    return paths;
}

function pausedForPowerSaver(id, powerSaver) {
    return powerSaver && id === "hyprmist";
}

function preference(id, choices) {
    var choice = choices[id] || {};
    // The compositor's manifest loader enables mist unless explicitly disabled.
    return id === "hyprmist" && typeof choice.enabled !== "boolean"
        ? Object.assign({}, choice, { enabled: true }) : choice;
}

function desired(id, choice, performance, powerSaver) {
    return choice.enabled && !(performance && choice.disableInPerformance) && !pausedForPowerSaver(id, powerSaver);
}

function loaderSettings(choices, performance, powerSaver) {
    var ids = Object.keys(choices);
    if (!ids.includes("hyprmist"))
        ids.push("hyprmist");
    var lines = ids.filter(id => /^[a-z0-9_-]+$/.test(id) && typeof preference(id, choices).enabled === "boolean")
        .map(id => "  [" + JSON.stringify(id) + "] = " + desired(id, preference(id, choices), performance, powerSaver) + ",");
    return "return {\n" + lines.join("\n") + "\n}\n";
}

function entries(installed, loaded, choices, performance, powerSaver) {
    return installed.map(plugin => {
        var actual = loaded.find(item => item.name.toLowerCase() === plugin.id);
        var choice = preference(plugin.id, choices);
        var enabled = choice.enabled ?? !!actual;
        var pausedForPower = enabled && pausedForPowerSaver(plugin.id, powerSaver);
        return Object.assign({}, plugin, {
            name: actual?.name || plugin.id,
            loaded: !!actual,
            enabled: enabled,
            disableInPerformance: choice.disableInPerformance === true,
            pausedForPowerSaver: pausedForPower,
            paused: pausedForPower || performance && choice.enabled && choice.disableInPerformance,
            desired: typeof choice.enabled === "boolean" ? desired(plugin.id, choice, performance, powerSaver) : !!actual && !pausedForPower
        });
    });
}
