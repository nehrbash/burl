import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {test} from 'node:test';
const source = path => readFileSync(new URL('../modules/launcher/' + path, import.meta.url), 'utf8');
const spotify = runInNewContext(source('SpotifyGraph.js') + '\n({nodes, links})');
const playlist = {uri:'spotify:playlist:test', name:'Playlist'};
const tracks = Array.from({length:120}, (_,i) => ({uri:`spotify:track:${i}`,name:`Track ${i}`, artist:'Artist'}));

test('opening a playlist includes all loaded tracks and only its hub', () => {
    const nodes = spotify.nodes([playlist, {uri:'other'}], [{uri:'unrelated'}], playlist,
        {[playlist.uri]:{status:'ready',tracks}}, 30);
    assert.equal(nodes.length,121);
    assert.equal(nodes[0].source,playlist);
    const index = Object.fromEntries(nodes.map((n,i) => [n.id,i]));
    const links = spotify.links(nodes,index);
    assert.equal(links.length,120);
    for (let i=0;i<links.length;i++) assert.deepEqual(Array.from(links[i]),[0,i+1]);
    assert.equal(nodes[120].source,tracks[119]);
});

test('pending and empty playlists retain a selectable hub; duplicate tracks share a node', () => {
    assert.equal(spotify.nodes([],tracks,playlist,{},30).length,1);
    assert.equal(spotify.nodes([],tracks,playlist,{[playlist.uri]:{tracks:[]}},30).length,1);
    assert.equal(spotify.nodes([],[],playlist,{[playlist.uri]:{tracks:[tracks[0],tracks[0],{}]}},30).length,2);
    assert.equal(spotify.nodes([playlist],tracks,null,{},30).length,31);
});

function navigation() {
    const content=source('Content.qml');
    const search={text:'>spotify mix',forceActiveFocus(){}};
    const graph={currentNode:0,nodes:[{id:'playlist-origin'}],indexById:{'playlist-origin':3},
        rebuild(){},flushSearch(){},selectNode(i){this.selected=i;}};
    const loads=[];
    const root={atSky:true,openedPlaylist:null,playlistReturn:null,kindMenuOpen:false,
        closeKindMenu(){root.kindMenuOpen=false;},visibilities:{closeWorld(){root.closed=true;}}};
    for (const name of ['openPlaylist','leavePlaylist','escape']) {
        const match=content.match(new RegExp('    function '+name+'\\(([^)]*)\\): void \\{([\\s\\S]*?)\\n    \\}'));
        assert.ok(match,name);
        root[name]=runInNewContext(`(function(${match[1].replace(/:\s*\w+/g,'')}) {${match[2]}})`,
            new Proxy({root,search,graph,SpotifySources:{loadPlaylist:uri=>loads.push(uri)}}, {
                has(){return true;},get(target,key){return key in target?target[key]:root[key];},
                set(target,key,value){root[key]=value;return true;}
            }));
    }
    return {root,search,graph,loads};
}

test('playlist entry preserves the query and Escape restores it before closing the world', () => {
    const {root,search,graph,loads}=navigation();
    root.openPlaylist(playlist);
    assert.equal(search.text,'');
    assert.equal(root.openedPlaylist,playlist);
    assert.deepEqual(loads,[playlist.uri]);
    root.openPlaylist(playlist);
    root.escape();
    assert.equal(root.openedPlaylist,null);
    assert.equal(search.text,'>spotify mix');
    assert.equal(graph.selected,3);
    assert.equal(root.closed,undefined);
    root.escape();
    assert.equal(root.closed,true);
});

test('Escape closes the playlist action menu before leaving its playlist', () => {
    const {root}=navigation();
    root.openPlaylist(playlist);
    root.kindMenuOpen=true;
    root.escape();
    assert.equal(root.kindMenuOpen,false);
    assert.equal(root.openedPlaylist,playlist);
    root.atSky=false;
    root.escape();
    assert.equal(root.closed,true);
});
