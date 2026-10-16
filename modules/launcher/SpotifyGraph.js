function nodes(playlists, recents, opened, contents, limit) {
    const selected = opened ? [opened] : playlists.slice(0, limit);
    const tracks = opened ? (contents[opened.uri]?.tracks ?? []) : recents.slice(0, limit);
    const result = selected.filter(p => p.uri).map(p => ({
        id: `spotify:pl:${p.uri}`, kind: 'spotifyPlaylist', source: p,
        label: p.name || '(playlist)', imageUrl: p.image || '',
        tooltip: [p.owner, p.trackCount ? `${p.trackCount} tracks` : ''].filter(Boolean).join('  •  ')
    }));
    const seen = new Set();
    for (const track of tracks) {
        if (!track.uri || seen.has(track.uri)) continue;
        seen.add(track.uri);
        result.push({id: `spotify:tr:${track.uri}`, kind: 'spotifyTrack', source: track,
            label: track.name || '(track)', imageUrl: track.image || '',
            tooltip: [track.artist, track.album].filter(Boolean).join('  •  '),
            searchMetadata: [track.artist || '', track.album || ''],
            spotifyAlbum: track.album || '', uri: track.uri, playlistUri: opened?.uri || ''});
    }
    return result;
}

function links(nodes, indexById) {
    const result = [];
    for (let i = 0; i < nodes.length; ++i) {
        const node = nodes[i];
        const parent = indexById[`spotify:pl:${node.playlistUri}`];
        if (node.playlistUri && parent !== undefined) result.push([parent, i]);
    }
    return result;
}
