import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {test} from 'node:test';
const {describe} = runInNewContext(readFileSync(new URL('../modules/launcher/NodePreview.js', import.meta.url), 'utf8') + '\n({describe})');
const preview = (node, options) => JSON.parse(JSON.stringify(describe(node, options)));

test('Spotify previews retain artist/album and distinguish playlist browsing from playback', () => {
    assert.deepEqual(preview({kind:'spotifyTrack', label:'Song', source:{artist:'Artist',album:'Album'}}),
        {kind:'Spotify track',title:'Song',details:['Artist','Album'],hint:'Enter · Play'});
    const playlist = preview({kind:'spotifyPlaylist',label:'Mix',source:{owner:'Owner',trackCount:0}}, {actionsAvailable:true});
    assert.deepEqual(playlist.details,['Owner','0 tracks']);
    assert.equal(playlist.hint,'Enter · Browse    Shift+Enter · Actions');
    assert.deepEqual(preview({kind:'spotifyPlaylist',source:{}}).details,[]);
});

test('each source contributes its own metadata without repeating title or inventing absent values', () => {
    assert.deepEqual(preview({kind:'app',label:'Editor',searchMetadata:['Editor','','Edit text']}).details,['Edit text']);
    assert.deepEqual(preview({kind:'file',label:'a.txt',source:{path:'/docs/a.txt'},tooltip:'/docs/a.txt'}).details,['/docs/a.txt']);
    assert.deepEqual(preview({kind:'mail',label:'Subject',source:{from:'Person',fromEmail:'person@example.org'}}).details,['Person','person@example.org']);
    assert.deepEqual(preview({kind:'event',source:{day:'2026-10-18',allDay:true}}).details,['2026-10-18 · All day']);
    assert.deepEqual(preview({kind:'roam',tags:['burl','design']}).details,['burl · design']);
});

test('hints reflect supplied action availability and non-actionable kinds', () => {
    assert.equal(preview({kind:'recent',source:{path:'/tmp/a'}},{emacsEnabled:false}).hint,'');
    assert.equal(preview({kind:'steam'},{primaryAvailable:false,actionsAvailable:true}).hint,'Shift+Enter · Actions');
    for (const kind of ['monitor','webFolder','unknown']) assert.equal(preview({kind}).hint,'');
    assert.equal(preview(null).title,'');
});

test('a source can supply a preview descriptor without changing the renderer or registry', () => {
    assert.deepEqual(preview({kind:'custom',label:'fallback',preview:{kind:'Custom source',title:'Specific title',details:['Detail','','Detail'],action:'Inspect'}}),
        {kind:'Custom source',title:'Specific title',details:['Detail'],hint:'Enter · Inspect'});
});
