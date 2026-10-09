# World tree render source

The shell uses the painted tree under `assets/images/tree/rendered/`, with a
geodesic growth map and `assets/shaders/tree-growth.frag.qsb`. Section branches,
roots, and controls remain live QML objects. The painted tree was created with
the built-in image generation tool; its prompt is saved beside this file.

`scripts/prepare-tree-growth.py` generates the arrival map through Blender.
`scripts/render-tree-layer.py` renders the same painted layer into transparent
animation frames and an editable Blender scene.
`scripts/render-world-tree.py` creates the separate procedural 3D study.

The packed `world-tree-layer.blend` contains the painted layer and its animated
growth material. `assets/videos/world-tree-growth.webm` is a two-second VP9
export with alpha; the interactive shell uses the shader directly.

Run from `files/burl` to regenerate the map, paths, scene, and video:

```sh
blender --background --python scripts/prepare-tree-growth.py -- \
  --source assets/images/tree/rendered/world-tree-painted.png \
  --output assets/images/tree/rendered/world-tree-growth.png \
  --paths components/widgets/PaintedTreePaths.js
blender --background --python scripts/render-tree-layer.py -- \
  --art assets/images/tree/rendered/world-tree-painted.png \
  --growth-map assets/images/tree/rendered/world-tree-growth.png \
  --output /tmp/burl-tree-layer
ffmpeg -framerate 24 -i /tmp/burl-tree-layer/growth-%04d.png \
  -c:v libvpx-vp9 -pix_fmt yuva420p -b:v 0 -crf 24 -auto-alt-ref 0 \
  assets/videos/world-tree-growth.webm
```

For the sidebar map, use `sidebar-bough.png` and `sidebar-bough-growth.png`,
set `--seed-u .01 --seed-v .53`, and omit `--paths`.

Compile the runtime shader with Qt Shader Tools:

```sh
qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o assets/shaders/tree-growth.frag.qsb assets/shaders/tree-growth.frag
```

Bark Brown 01 textures by Rob Tuytel from
[Poly Haven](https://polyhaven.com/a/bark_brown_01), licensed CC0.
Texture download metadata powered by the Poly Haven API.

`rendered/sidebar-grown.png` uses `sidebar-grown-prompt.txt` with the painted
world tree as its material reference. Its trunk and root foot form one
continuous silhouette. The owl aligns with its upper hollow; the pot, tray,
and status controls use live recessed settings.
