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

function desired(choice, performance) {
    return choice.enabled && !(performance && choice.disableInPerformance);
}

function loaderSettings(choices, performance) {
    var lines = Object.keys(choices).filter(id => /^[a-z0-9_-]+$/.test(id) && typeof choices[id].enabled === "boolean")
        .map(id => "  [" + JSON.stringify(id) + "] = " + desired(choices[id], performance) + ",");
    return "return {\n" + lines.join("\n") + "\n}\n";
}

function entries(installed, loaded, choices, performance) {
    return installed.map(plugin => {
        var actual = loaded.find(item => item.name.toLowerCase() === plugin.id);
        var choice = choices[plugin.id] || {};
        return Object.assign({}, plugin, {
            name: actual?.name || plugin.id,
            loaded: !!actual,
            enabled: choice.enabled ?? !!actual,
            disableInPerformance: choice.disableInPerformance === true,
            paused: performance && choice.enabled && choice.disableInPerformance,
            desired: typeof choice.enabled === "boolean" ? desired(choice, performance) : !!actual
        });
    });
}
