function executableName(command) {
    return (command[0] ?? "").split("/").pop();
}

function legacyEntry(command, entries) {
    if (!command.length) return null;
    const matches = entries.filter(entry => executableName(entry.command) === executableName(command)
        && JSON.stringify(entry.command.slice(1)) === JSON.stringify(command.slice(1)));
    return matches.length === 1 ? matches[0] : null;
}

function resolve(id, legacy, entries, fallback) {
    if (id) {
        const entry = entries.find(entry => entry.id === id);
        if (!entry) throw new Error("Application is no longer installed: " + id);
        return { command: Array.from(entry.command), workingDirectory: entry.workingDirectory ?? "" };
    }
    if (!legacy.length) return { command: [fallback], workingDirectory: "" };
    const current = legacyEntry(legacy, entries);
    if (current) return { command: Array.from(current.command), workingDirectory: current.workingDirectory ?? "" };
    const command = Array.from(legacy);
    if (command[0].startsWith("/gnu/store/")) {
        const candidates = entries.filter(entry => executableName(entry.command) === executableName(command));
        const executables = [...new Set(candidates.map(entry => entry.command[0]))];
        if (executables.length === 1) command[0] = executables[0];
    }
    return { command, workingDirectory: "" };
}

function terminalFlag(command) {
    const name = executableName(command);
    if (["foot", "footclient", "alacritty", "kitty", "konsole", "xterm", "uxterm", "urxvt", "rxvt", "st", "ghostty", "x-terminal-emulator"].includes(name)) return "-e";
    if (["gnome-terminal", "kgx", "ptyxis"].includes(name)) return "--";
    if (name === "xfce4-terminal") return "-x";
    return null;
}

function terminalCommand(command, child) {
    if (!command.length) throw new Error("No terminal selected");
    if (command.some(arg => ["-e", "--command", "-x", "--execute", "--"].includes(arg)))
        return [...command, ...child];
    const flag = terminalFlag(command);
    if (!flag) throw new Error("Terminal needs an explicit child-command option: " + executableName(command));
    return [...command, flag, ...child];
}

function fileCommand(id, legacy, entries, path) {
    const entry = id ? entries.find(entry => entry.id === id) : legacyEntry(legacy, entries);
    if (id && !entry) throw new Error("Application is no longer installed: " + id);
    if (entry) return ["gtk-launch", entry.id, path];
    return [...resolve("", legacy, entries, "xdg-open").command, path];
}
