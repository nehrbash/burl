const scopes = {
    apps: ['app'], files: ['file'], roam: ['roam'], recents: ['recent'], bookmarks: ['bookmark'],
    wallpaper: ['wallpaper'], web: ['webBookmark', 'webFolder', 'webHistory', 'webTab'],
    webbm: ['webBookmark'], webfolder: ['webFolder'], webhist: ['webHistory'], tabs: ['webTab'],
    spotify: ['spotifyPlaylist', 'spotifyTrack'], playlists: ['spotifyPlaylist'], tracks: ['spotifyTrack'],
    clients: ['client'], monitors: ['monitor'], workspaces: ['workspace'], category: ['category'],
    projects: ['project'], mail: ['mail'], cal: ['event'], clip: ['clip'], emoji: ['emoji']
};
const aliases = {
    app: 'apps', file: 'files', recent: 'recents', bookmark: 'bookmarks', wallpapers: 'wallpaper',
    tab: 'tabs', playlist: 'playlists', track: 'tracks', client: 'clients', monitor: 'monitors',
    workspace: 'workspaces', categories: 'category', project: 'projects', calendar: 'cal',
    event: 'cal', clipboard: 'clip'
};

function kindsFor(keyword) {
    const key = keyword.trim().toLowerCase();
    return Object.prototype.hasOwnProperty.call(scopes, key) ? scopes[key]
        : Object.prototype.hasOwnProperty.call(aliases, key) ? scopes[aliases[key]] : null;
}

function markerAt(text, pos, prefix) {
    if (!prefix || !text.startsWith(prefix, pos) || (pos > 0 && !/\s/.test(text[pos - 1])))
        return null;
    const match = /^[a-z]+(?:\s*\|\s*[a-z]+)*/i.exec(text.slice(pos + prefix.length));
    if (!match) return null;
    const end = pos + prefix.length + match[0].length;
    if (end < text.length && !/\s/.test(text[end])) return null;
    const kinds = [];
    for (const keyword of match[0].split(/\s*\|\s*/)) {
        const resolved = kindsFor(keyword);
        if (!resolved) return null;
        for (const kind of resolved)
            if (!kinds.includes(kind)) kinds.push(kind);
    }
    return {start: pos, end, kinds};
}

function regexEndAt(text, pos) {
    if (!text.startsWith('re:/', pos) || (pos > 0 && !/\s/.test(text[pos - 1])))
        return pos;
    let escaped = false;
    let inClass = false;
    for (let end = pos + 4; end < text.length; end++) {
        const ch = text[end];
        if (escaped) { escaped = false; continue; }
        if (ch === '\\') { escaped = true; continue; }
        if (ch === '[') inClass = true;
        else if (ch === ']') inClass = false;
        else if (ch === '/' && !inClass) return end + 1;
    }
    return text.length;
}

function parse(text, prefix) {
    if (!prefix || text.startsWith('?')) return null;
    // An unknown leading command belongs to the actions overlay.
    if (text.startsWith(prefix) && !markerAt(text, 0, prefix)) return null;
    const markers = [];
    for (let pos = 0; pos < text.length; pos++) {
        const regexEnd = regexEndAt(text, pos);
        if (regexEnd > pos) { pos = regexEnd - 1; continue; }
        const marker = markerAt(text, pos, prefix);
        if (marker) {
            markers.push(marker);
            pos = marker.end - 1;
        }
    }
    if (!markers.length) return null;
    const shared = text.slice(0, markers[0].start).trim();
    const segments = [];
    for (let i = 0; i < markers.length; i++) {
        const marker = markers[i];
        const local = text.slice(marker.end, i + 1 < markers.length ? markers[i + 1].start : text.length).trim();
        const q = [shared, local].filter(Boolean).join(' ');
        for (const kind of marker.kinds)
            if (!segments.some(segment => segment.kind === kind && segment.q === q))
                segments.push({kind, q});
    }
    return segments;
}

function complete(text, prefix) {
    if (!prefix || text.startsWith('?')) return null;
    const pos = text.lastIndexOf(prefix);
    if (pos < 0 || (pos > 0 && !/\s/.test(text[pos - 1]))) return null;
    for (let start = 0; start <= pos; start++) {
        const end = regexEndAt(text, start);
        if (end > pos) return null;
        if (end > start) start = end - 1;
    }
    const tail = text.slice(pos + prefix.length);
    if (!/^[a-z]*(?:\s*\|\s*[a-z]*)*$/i.test(tail)) return null;
    const pipe = tail.lastIndexOf('|');
    const partial = tail.slice(pipe + 1).trimStart().toLowerCase();
    if (!partial) return null;
    const preceding = pipe < 0 ? [] : tail.slice(0, pipe).split(/\s*\|\s*/);
    if (preceding.some(keyword => !kindsFor(keyword))) return null;
    if (kindsFor(partial)) return text + ' ';
    const hits = Object.keys(scopes).filter(keyword => keyword.startsWith(partial));
    if (!hits.length) return null;
    let common = hits[0];
    for (const hit of hits.slice(1)) {
        let length = 0;
        while (length < common.length && common[length] === hit[length]) length++;
        common = common.slice(0, length);
    }
    if (common.length <= partial.length) return null;
    return text.slice(0, text.length - partial.length) + common + (hits.length === 1 ? ' ' : '');
}
