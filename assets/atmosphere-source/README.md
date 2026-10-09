Four Blender volumes supply independently billowing cloud banks. Tree and sky banks frame clear central space; the foreground veil gathers around roots. The dream volumes use a perspective camera matching the painted hall. Each bank has a separate noise seed and phase, with periodic translation and density evolution. There is no global rotation.

Render with Blender 4.5:

```sh
blender -b --gpu-backend vulkan --python files/burl/scripts/render-atmospheres.py -- --output /tmp/clouds --scene tree
ffmpeg -y -start_number 1 -i /tmp/clouds/tree-%03d.png -vf tile=8x4 -frames:v 1 files/burl/assets/images/nocturne/tree-clouds.png
```

Repeat for `veil`, `sky`, and `dream`. Copy the saved `.blend` files here. Each 10240×2880 atlas holds 32 frames at 1280×720. Runtime interpolation blends adjacent frames, including the loop seam. Playback stops while hidden, under reduced motion, or in game mode.

`AstralScene.qml` composes three architectural depth groups with separate
camera travel and independent drift. The 3762×3762 `astral-fragments.png` atlas
contains six ruins, two planets, and the throne/table in a 3×3 grid. Each
1254×1254 cell is generated separately, then packed without resampling. The
1254×1254 `cloud-island.png` supplies a complete cloud silhouette, instanced
with independent drift, rotation and scale between groups. Existing Blender fog billows
between the solid clouds and architecture. These are individual transparent
cutouts, not a full-screen painted scene.

`astral-glass.png` is a 1774×887 transparent 4×2 atlas. Eight shards drift on
independently phased paths. Image crops are fixed before rotation to prevent neighbouring atlas cells from
leaking through transformed item clips in the desktop renderer.
Architecture drifts over 110 seconds. Cloud cutouts follow a separate 32-second
cycle, with denser fog billowing over 22–36 seconds.
All scene motion stops when hidden, inactive, reduced motion is enabled, or
game mode is active. Decorations do not accept input.

The cutout assets were generated with the built-in image tool; complete
prompts live here under matching names. `cathedral-reference.png` preserves the
user's style reference. Atlas cell dimensions in AstralFragment
and AstralGlass must match their source images.

Sky uses distant planets and low cloud banks with small cathedral tips; the tree
room descends with its host during ascent. The lunar shader shades the crimson
moon painting with the weather phase while retaining its emissive corona.
`astral-refinement-prompts.txt` records the cloud, moon and registered tree edit.
