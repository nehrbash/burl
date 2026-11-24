function tailscale(data) {
    if (!data || typeof data.BackendState !== "string")
        throw new Error("Invalid Tailscale status");
    const peers = Object.values(data.Peer || {}).map(p => ({
        name: p.HostName || p.DNSName || "Peer",
        dns: (p.DNSName || "").replace(/\.$/, ""),
        ip: (p.TailscaleIPs || [])[0] || "",
        online: p.Online === true,
        exitNode: p.ExitNode === true,
        exitAvailable: p.ExitNodeOption === true,
        connection: p.CurAddr ? "Direct" : p.Active && p.Relay ? "Relay" : "Idle"
    })).sort((a, b) => Number(b.online) - Number(a.online) || a.name.localeCompare(b.name));
    return {
        state: data.BackendState,
        name: data.Self?.HostName || "",
        ip: (data.TailscaleIPs || data.Self?.TailscaleIPs || [])[0] || "",
        tailnet: data.CurrentTailnet?.Name || "",
        health: data.Health || [],
        authUrl: /^https:\/\//.test(data.AuthURL || "") ? data.AuthURL : "",
        peers: peers
    };
}

function timestamp(value) {
    const ms = Date.parse(value || "");
    // Syncthing reports "never" as the Unix epoch or Go's zero time.
    return ms > Date.UTC(2000, 0, 1) ? ms : 0;
}

function ago(ms, now) {
    if (!ms) return "";
    const s = Math.max(0, Math.round((now - ms) / 1000));
    return s < 60 ? "just now" : s < 3600 ? Math.floor(s / 60) + "m ago"
        : s < 86400 ? Math.floor(s / 3600) + "h ago" : Math.floor(s / 86400) + "d ago";
}

function peer(config, connection, stats, completion) {
    const connected = connection?.connected === true;
    return {
        id: config.deviceID, name: config.name || config.deviceID, paused: config.paused === true,
        connected: connected, address: connected ? connection.address || "" : "",
        lastSeen: connected ? Date.now() : timestamp(stats?.lastSeen),
        completion: typeof completion?.completion === "number" ? completion.completion : -1,
        needed: Math.max(0, Number(completion?.needItems || 0) + Number(completion?.needDeletes || 0))
    };
}

function folder(config, status, stats) {
    const needed = Math.max(0, Number(status.needTotalItems || 0));
    const total = Math.max(0, Number(status.globalBytes || 0));
    const remaining = Math.max(0, Number(status.needBytes || 0));
    const errors = Number(status.pullErrors || 0);
    const state = config.paused ? "Paused" : status.error || errors || status.state === "error" ? "Error"
        : status.state === "scanning" || status.state === "scan-waiting" ? "Scanning"
        : status.state === "syncing" || status.state === "sync-waiting" ? "Syncing"
        : needed ? "Out of sync" : Number(status.receiveOnlyTotalItems || 0) ? "Local changes" : "Up to date";
    return {
        id: config.id, name: config.label || config.id, path: config.path,
        paused: config.paused === true, state: state, needed: needed,
        remaining: remaining, errors: errors,
        lastScan: timestamp(stats?.lastScan), lastChange: timestamp(stats?.lastFile?.at),
        lastFile: stats?.lastFile?.filename || "",
        progress: config.paused || status.error ? 0 : total ? Math.max(0, Math.min(1, (total - remaining) / total)) : needed ? 0 : 1
    };
}

function localUrl(value) {
    return /^http:\/\/(127\.0\.0\.1|localhost|\[::1\])(:[0-9]{1,5})?$/.test(value);
}

function apiKey(xml) {
    const match = /<apikey>\s*([A-Za-z0-9_-]+)\s*<\/apikey>/.exec(xml);
    return match ? match[1] : "";
}

function validResponse(path, data) {
    if (!data || typeof data !== "object") return false;
    if (path === "system/status") return typeof data.myID === "string";
    if (path === "system/connections") return data.connections && typeof data.connections === "object";
    if (path === "config/devices") return Array.isArray(data) && data.every(d => typeof d.deviceID === "string");
    if (path === "config/folders") return Array.isArray(data) && data.every(f => typeof f.id === "string");
    if (path.startsWith("db/status?")) return typeof data.state === "string";
    if (path.startsWith("db/completion?")) return typeof data.completion === "number";
    return true;
}
