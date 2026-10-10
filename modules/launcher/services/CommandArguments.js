.pragma library

function parseArguments(text) {
    const args = [];
    let token = "", quote = "", started = false;
    for (let i = 0; i < text.length; ++i) {
        const char = text[i];
        if (char === "\\" && quote !== "'") {
            if (++i >= text.length) return {args: [], error: "Finish the escape or remove the trailing backslash."};
            const next = text[i];
            if (quote === '"' && !['"', "\\", "$", "`", "\n"].includes(next)) token += "\\";
            if (next !== "\n") token += next;
            started = true;
        } else if (quote) {
            if (char === quote) quote = "";
            else token += char;
        } else if (char === "'" || char === '"') {
            quote = char;
            started = true;
        } else if (/\s/.test(char)) {
            if (started) { args.push(token); token = ""; started = false; }
        } else {
            token += char;
            started = true;
        }
    }
    if (quote) return {args: [], error: quote === "'" ? "Close the single quote before running." : "Close the double quote before running."};
    if (started) args.push(token);
    return {args, error: ""};
}

function formatArguments(args) {
    return Array.from(args).map(arg => /^[A-Za-z0-9_./:@%+=,-]+$/.test(arg)
        ? arg : "'" + arg.replace(/'/g, "'\\''") + "'").join(" ");
}

function executableFor(action) {
    return String(action.command?.[0] ?? "").split("/").pop();
}

function keywordFor(action) {
    if (action.keyword) return String(action.keyword);
    return String(action.name ?? executableFor(action)).toLowerCase().trim()
        .replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "") || executableFor(action);
}

function validKeyword(value) {
    return /^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(value);
}

function supportsArguments(action) {
    return !["autocomplete", "setText", "setMode"].includes(action.command?.[0]);
}

function aliasesFor(action) {
    const keyword = keywordFor(action).toLowerCase();
    const executable = executableFor(action).toLowerCase();
    return supportsArguments(action) && executable ? [keyword, executable] : [keyword];
}

function invocation(action, text) {
    const command = typeof action.command === "string" ? [] : Array.from(action.command ?? []);
    if (!command.length || typeof command[0] !== "string" || !command[0].trim() || command.some(arg => typeof arg !== "string" || arg.includes("\0")))
        return {command: [], error: "Set an executable and valid arguments in Launcher settings."};
    const parts = text.trim().match(/^(\S+)(?:\s+([\s\S]*))?$/);
    const tail = parts?.[2] ?? "";
    if (!parts || !aliasesFor(action).includes(parts[1].toLowerCase()) || !tail.trim())
        return {command, error: ""};
    if (!action.acceptArgs || !supportsArguments(action))
        return {command: [], error: "This command does not accept extra arguments. Remove them or enable arguments in Launcher settings."};
    const parsed = parseArguments(tail);
    if (parsed.error) return {command: [], error: parsed.error};
    if (parsed.args.some(arg => arg.includes("\0")))
        return {command: [], error: "Arguments cannot contain a null character."};
    return {command: command.concat(parsed.args), error: ""};
}

function isSessionShorthand(command) {
    return command.length === 1
        || (command.length === 2 && ["loginctl", "systemctl"].includes(command[0]))
        || (command.length === 3 && command[0] === "loginctl"
            && command[1] === "terminate-user" && command[2] === "");
}
