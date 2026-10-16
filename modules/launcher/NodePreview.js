function text(value) {
    return typeof value === "string" ? value.trim() : "";
}

function rows(values) {
    return values.map(text).filter((value, index, all) => value && all.indexOf(value) === index);
}

function fileDetails(node) {
    return rows([node.source?.path, node.path, node.tooltip]);
}

const adapters = {
    spotifyTrack: node => ({kind: "Spotify track", action: "Play", details: rows([node.source?.artist, node.source?.album])}),
    spotifyPlaylist: node => {
        const source = node.source || {};
        const count = source.trackCount;
        return {kind: "Spotify playlist", action: "Browse", details: rows([
            source.owner,
            typeof count === "number" && Number.isInteger(count) && count >= 0
                ? `${count} ${count === 1 ? "track" : "tracks"}` : ""
        ])};
    },
    steam: node => ({kind: "Steam game", action: "Play", details: ["Installed locally"]}),
    app: node => ({kind: "Application", action: "Launch", details: rows([
        node.entry?.comment || node.searchMetadata?.[2],
        node.entry?.genericName || node.searchMetadata?.[0]
    ])}),
    file: node => ({kind: "File", action: "Open", details: fileDetails(node)}),
    recent: node => ({kind: "Recent file", action: "Open", emacs: true, details: fileDetails(node)}),
    project: node => ({kind: "Project", action: "Open", emacs: true, details: rows([node.source?.root])}),
    bookmark: node => ({kind: "Emacs bookmark", action: "Open", emacs: true, details: []}),
    roam: node => ({kind: "Roam note", action: "Open", emacs: true, details: rows([
        Array.isArray(node.tags) ? node.tags.join(" · ") : ""
    ])}),
    mail: node => ({kind: "Mail", action: "Open", emacs: true, details: rows([node.source?.from, node.source?.fromEmail])}),
    event: node => ({kind: "Calendar event", action: "Open", emacs: true, details: rows([
        [text(node.source?.day), node.source?.allDay ? "All day" : text(node.source?.time)].filter(Boolean).join(" · ")
    ])}),
    client: node => ({kind: "Open window", action: "Focus", details: rows([
        node.clientClass, node.clientWorkspace !== undefined ? `Workspace ${node.clientWorkspace}` : ""
    ])}),
    workspace: node => ({kind: "Workspace", action: "Switch", details: rows([node.workspaceMonitor])}),
    monitor: node => ({kind: "Monitor", details: rows([node.tooltip])}),
    category: node => ({kind: "Application category", action: "Browse", details: []}),
    webBookmark: node => ({kind: "Web bookmark", action: "Open", details: rows([node.tooltip])}),
    webHistory: node => ({kind: "Web history", action: "Open", details: rows([node.tooltip])}),
    webTab: node => ({kind: "Browser tab", action: "Focus", details: rows([node.tooltip])}),
    webFolder: node => ({kind: "Bookmark folder", details: []}),
    wallpaper: node => ({kind: "Wallpaper", action: "Apply", details: rows([node.tooltip])}),
    emoji: node => ({kind: "Emoji", action: "Copy", details: []}),
    clip: node => ({kind: "Clipboard", action: "Copy", details: []})
};

function describe(node, options) {
    if (!node) return {kind: "", title: "", details: [], hint: ""};
    const settings = options || {};
    const adapter = adapters[node.kind];
    const value = node.preview || (adapter ? adapter(node) : {kind: "", details: rows([node.tooltip])});
    const title = text(value.title || node.label);
    const primary = settings.primaryAvailable !== false && (!value.emacs || settings.emacsEnabled !== false);
    const hints = [];
    if (value.action && primary) hints.push(`Enter · ${value.action}`);
    if (settings.actionsAvailable) hints.push("Shift+Enter · Actions");
    return {kind: text(value.kind), title, details: rows(Array.isArray(value.details) ? value.details : []).filter(detail => detail !== title), hint: hints.join("    ")};
}
