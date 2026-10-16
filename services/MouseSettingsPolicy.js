.pragma library

var keys = ["accel_profile", "sensitivity", "natural_scroll", "left_handed"];

function valid(key, value) {
    if (key === "accel_profile")
        return value === "adaptive" || value === "flat";
    if (key === "sensitivity")
        return typeof value === "number" && isFinite(value) && value >= -1 && value <= 1;
    return (key === "natural_scroll" || key === "left_handed") && typeof value === "boolean";
}

function overrides(value) {
    var result = {};
    for (const key of keys) {
        if (valid(key, value[key]))
            result[key] = value[key];
    }
    return result;
}

function read(key, text) {
    const data = JSON.parse(text);
    const value = key === "accel_profile" ? data.str : key === "sensitivity" ? data.float : data.bool;
    if (key === "accel_profile" && typeof value === "string")
        return value;
    if (!valid(key, value))
        throw new Error("Invalid compositor value for " + key);
    return value;
}

function command(values) {
    const entries = Object.keys(values).map(key => {
        if (!valid(key, values[key]))
            throw new Error("Invalid mouse setting: " + key);
        return key + " = " + JSON.stringify(values[key]);
    });
    return "hl.config({ input = { " + entries.join(", ") + " } })";
}

function matches(actual, requested) {
    return Object.keys(requested).every(key => typeof requested[key] === "number"
        ? Math.abs(actual[key] - requested[key]) < 0.00001 : actual[key] === requested[key]);
}
