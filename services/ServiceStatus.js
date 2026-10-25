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

function folder(config, status) {
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
    return true;
}
