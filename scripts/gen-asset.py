#!/usr/bin/env python3
r"""Generate tree/decoration assets for the shell with gpt-image-1.

Usage: gen-asset.py "<prompt>" <1024x1024|1536x1024|1024x1536> <out.png> [quality] [background]

  quality      "high" (default) | "medium" for cheap drafts
  background   "transparent" (default) | "opaque"

Use "opaque" for full-bleed textures (bark / parchment card backgrounds): a
transparent request makes the model paint a cut-out *shape* instead of an
edge-to-edge fill.

Full method (decision rule, measurement snippets, failure catalogue, model
landscape): the `gen-image` skill, ~/src/dotfiles/files/claude/skills/gen-image/.

=== BEFORE YOU GENERATE: match generation size to DRAW size ===

Generated raster is right for LARGE illustration rendered near its native size
(trunk.png, roots-large.png, root-turnup.png, the sloths, owl.png). It is WRONG
for small chrome: a 1024px illustration minified past ~4x averages into blobs —
fine detail dies and any paint close in value to its background disappears.

  target <= ~64px (icons, rings, frames, badges)  -> hand-author an SVG at the
                                                     render size, or a QML Shape
  target >  ~64px (illustrations, textures)       -> generate here

Reference for hand-authored chrome, read it before authoring:
modules/bar/components/workspaces/images/moss-ring.svg. Its predecessors
ivy-frame.png and ivy-ring.png were both generated, both deleted; ivy-ring.png
measured perfectly (81.5% hole, 5.1px stroke, near-zero icon contact) and still
looked bad because its bark-brown vine was drawn on bark. The eye is the gate,
not the numbers.

=== MODEL PIN ===

gpt-image-1 is pinned deliberately. gpt-image-2 (OpenAI's current flagship as of
2026-08) does NOT support transparent backgrounds per OpenAI's own docs, so
"upgrading" would break nearly every asset here. gpt-image-1.5 is an untested
candidate. Re-verify before touching this.

=== POST-PROCESSING (required) ===

Key from `pass show api.openai.com/apikey`. The model bakes a soft glow into the
alpha channel regardless of prompt. `convert` and `rsvg-convert` are on PATH
(imagemagick is declared in desktop/burl.scm); PIL/Pillow is NOT installed.

    convert out.png -channel A -level 55x95% +channel -trim +repage clean.png
    convert clean.png -evaluate Multiply 0.73 matched.png   # sit on trunk bark

Measure colour as the ALPHA-WEIGHTED opaque-paint mean; a plain mean includes
garbage RGB from transparent pixels and reads grey:

    a=$(convert f.png -alpha extract -format "%[fx:mean]" info:)
    convert f.png -background black -alpha remove -alpha off \
      -format "%[fx:mean.r] %[fx:mean.g] %[fx:mean.b]\n" info: \
      | awk -v a=$a '{printf "#%02X%02X%02X\n", $1/a*255, $2/a*255, $3/a*255}'

Do not push the BLUE channel to shift yellow-olive toward olive: measured
result is grey-teal leaves and violet dark outlines.

Verify transparency by flattening over magenta; preview/measure SVGs with
`rsvg-convert -w N -h N` (ImageMagick's SVG renderer flattens `mask` to a filled
square and silently lies); tile with `-tile f.png -draw ...`, never `tile:f.png`
(which discards alpha).

=== KNOWN MODEL FAILURES — design around them ===

- Asked for an edge-to-edge tileable strip it paints a centred object with
  rounded caps and margins, and adds a brown log/dirt plinth under moss even
  when told not to. Generate wide, crop the interior, build tileability in post.
- It renders bright chartreuse GRASS when asked for moss. Attack it by name:
  "emphatically NOT grass: no blades, no spikes, nothing pointed, only soft
  rounded lumps like velvet". Drop the word "lichen".
- Demand coarseness so detail survives the downscale: "about twelve LARGE
  chunky lobes, no fine fuzz, big simple shapes only".
- Parallel invocations race on a shared temp filename — always use unique
  temp names.

=== HOUSE STYLE PROMPT SUFFIX (keep assets consistent) ===

    Cozy flat 2D storybook illustration style with soft subtle shading and
    slight paper texture, warm woodland palette: olive greens (#46602c,
    #567436, #688a41) and warm browns (#4a3425, #6b5040, dark edges #2f2117).
    Crisp opaque paint, no glow, no halo. Fully transparent background,
    no scenery.

One-shot prompting is structurally wrong for an on-style asset SET (style drift
per call). See the skill's references/model-landscape.md for the trained-style
alternatives; this script is not the tool for that job.
"""
import json, base64, subprocess, sys, urllib.request

def gen(prompt, size, out, quality="high", background="transparent"):
    key = subprocess.run(["pass", "show", "api.openai.com/apikey"],
                         capture_output=True, text=True, check=True).stdout.strip()
    body = json.dumps({
        "model": "gpt-image-1",
        "prompt": prompt,
        "size": size,
        "quality": quality,
        "background": background,
        "output_format": "png",
        "n": 1,
    }).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/images/generations", data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        d = json.load(r)
    open(out, "wb").write(base64.b64decode(d["data"][0]["b64_json"]))
    print("saved", out)

if __name__ == "__main__":
    gen(sys.argv[1], sys.argv[2], sys.argv[3], *(sys.argv[4:6] or ["high"]))
