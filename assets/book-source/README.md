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

From the repository root, render a section at full resolution and pack its opening:

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

The enlarged task book uses 49 poses at 1368×950:

```sh
blender --background --factory-startup --python scripts/render-book.py -- \
  --variant tasks --frames 49 --output /tmp/burl-tasks --blend /tmp/burl-tasks.blend
ffmpeg -y -start_number 1 -i /tmp/burl-tasks/book-%02d.png \
  -vf 'scale=1368:950,tile=7x7' -frames:v 1 assets/images/book/tasks/opening-sheet.png
cp /tmp/burl-tasks/book-49.png assets/images/book/tasks/book-25.png
cp /tmp/burl-tasks/registration.json assets/images/book/tasks/
```

Keep the decoded task atlas below 256 MiB. All resting poses
are 1440×1000; other sections use 25 opening frames at 720×500. `book-25.png` names the resting pose in every
section. `registration.json` defines the rendered page rectangle. Update the
four registration constants in `Grimoire.qml` when changing the camera.
Regression checks compare them and verify projected hinge and cover motion.
