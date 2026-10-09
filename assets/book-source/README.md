# Blender book

`grimoire.blend` contains the dark leather boards, thin gilt rims, curved
parchment, stacked signatures, and two turning flyleaves. Live QML widgets
occupy the registered page. The fixed camera and cover hinge are shared by
all five section designs.

`foil/<section>.png` supplies the cover texture. Built-in image generation used
the supplied black-and-iridescent occult book reference (`foil/reference.png`); the corresponding
`foil/<section>-prompt.txt` files contain the complete prompts. The motifs are
Dashboard's branching seals, Media's resonance diagram, Performance's
astrolabe, Weather's lunar diagram, and Tasks' ritual ledger. Texture brightness
controls metallic reflectance, keeping the dark leather matte and the engraving
reflective. Materials and geometry are authored in `scripts/render-book.py`.

From `files/burl`, render a section at full resolution and pack its opening:

```sh
blender --background --factory-startup --python scripts/render-book.py -- \
  --variant media --output /tmp/burl-media --blend /tmp/burl-media.blend
ffmpeg -y -start_number 1 -i /tmp/burl-media/book-%02d.png \
  -vf 'scale=720:500,tile=5x5' -frames:v 1 assets/images/book/media/opening-sheet.png
cp /tmp/burl-media/book-25.png assets/images/book/media/
```

Supported variants: `dashboard`, `media`, `performance`, `weather`, and `tasks`.
Dashboard assets live directly in `assets/images/book/`; the others use their
section subdirectories. `Grimoire.qml` selects them by section ID.

The opening uses a 3600×2500 sprite sheet; the resting pose uses a 1440×1000
still. `registration.json` defines the rendered page rectangle. Update the four
registration constants in `Grimoire.qml` when changing the camera. Regression
checks compare them and verify projected hinge and cover motion.
