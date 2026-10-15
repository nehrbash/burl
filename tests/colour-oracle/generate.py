#!/usr/bin/env python3
"""Freeze the Python CLI's colour and theme output as fixtures for the C++ port.

The Python CLI was removed after commit 295c9dc. To regenerate, check that
commit out and run, from the burl checkout:
    guix shell python python-materialyoucolor python-pillow -- \
        python3 tests/colour-oracle/generate.py
"""
import json
import os
import random
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent

# burl.utils.paths resolves XDG directories at import time.
SANDBOX = Path(tempfile.mkdtemp(prefix="burl-oracle-"))
for var in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"):
    os.environ[var] = str(SANDBOX / var.lower())
os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
sys.path.insert(0, str(ROOT / "cli"))

import subprocess  # noqa: E402

from PIL import Image  # noqa: E402
from materialyoucolor.hct import Hct  # noqa: E402
from materialyoucolor.utils.color_utils import argb_from_rgb  # noqa: E402

from burl.utils import theme  # noqa: E402
from burl.utils.colourfulness import calc_colourfulness, get_variant  # noqa: E402
from burl.utils.material.generator import gen_scheme  # noqa: E402
from burl.utils.material.score import score  # noqa: E402
from burl.utils.scheme import scheme_variants  # noqa: E402

SEEDS = [
    0xFF6750A4, 0xFFB3261E, 0xFF00639B, 0xFF006E1C, 0xFF7D5260, 0xFF9C4146,
    0xFFFFB4AB, 0xFF4285F4, 0xFFEA4335, 0xFFFBBC05, 0xFF34A853, 0xFF000000,
    0xFFFFFFFF, 0xFF808080, 0xFF1A1C1E, 0xFFF5E0DC, 0xFF2E3440, 0xFF88C0D0,
    0xFFA3BE8C, 0xFFD08770, 0xFF5A77AB, 0xFF3B2F2F, 0xFF00FFFF, 0xFFFF00FF,
]


class Selection:
    def __init__(self, variant, flavour, mode):
        self.variant, self.flavour, self.mode = variant, flavour, mode


def hex8(argb):
    return f"{argb & 0xFFFFFFFF:08X}"


def schemes():
    cases = []
    for seed in SEEDS:
        for variant in scheme_variants:
            for mode in ("light", "dark"):
                for flavour in ("default", "hard"):
                    case = {"seed": hex8(seed), "variant": variant, "mode": mode, "flavour": flavour}
                    try:
                        case["colours"] = gen_scheme(Selection(variant, flavour, mode), Hct.from_int(seed))
                    except ArithmeticError as error:
                        # Achromatic seeds divide by zero in the temperature cache.
                        case["error"] = type(error).__name__
                    cases.append(case)
    return cases


def synthetic_images(directory):
    """Deterministic images covering flat, gradient, noisy and grey inputs."""
    rng = random.Random(20261015)
    images = {}

    def save(name, image):
        path = directory / name
        image.save(path)
        images[name] = path

    for name, colour in (("flat-blue.png", (40, 90, 200)), ("flat-grey.png", (128, 128, 128)),
                         ("flat-light.png", (235, 230, 220))):
        save(name, Image.new("RGB", (64, 48), colour))

    gradient = Image.new("RGB", (128, 72))
    gradient.putdata([(x * 2, y * 3, 255 - x * 2) for y in range(72) for x in range(128)])
    save("gradient.png", gradient)

    noise = Image.new("RGB", (96, 96))
    noise.putdata([tuple(rng.randrange(256) for _ in range(3)) for _ in range(96 * 96)])
    save("noise.png", noise)

    blocks = Image.new("RGB", (120, 80))
    palette = [(200, 40, 40), (30, 140, 60), (240, 200, 40), (20, 20, 30), (230, 230, 240)]
    blocks.putdata([palette[(x // 24 + y // 16) % len(palette)] for y in range(80) for x in range(120)])
    save("blocks.png", blocks)

    alpha = Image.new("RGBA", (64, 64))
    alpha.putdata([(x * 4, 100, y * 4, (x + y) * 2) for y in range(64) for x in range(64)])
    save("alpha.png", alpha)

    # The real pipeline scores a 128px JPEG thumbnail, so freeze one decode path.
    photo = noise.resize((128, 128), Image.BILINEAR)
    photo.save(directory / "thumbnail.jpg", "JPEG")
    images["thumbnail.jpg"] = directory / "thumbnail.jpg"
    return images


def image_cases(directory):
    cases = []
    for name, path in synthetic_images(directory).items():
        with Image.open(path) as img:
            rgb = img.convert("RGB")
            colourfulness = calc_colourfulness(rgb)
            variant = get_variant(rgb)
            one = rgb.copy()
            one.thumbnail((1, 1), Image.LANCZOS)
            pixel = one.getpixel((0, 0))
            tone = Hct.from_int(argb_from_rgb(*pixel)).tone
        cases.append({"image": name, "score": hex8(score(str(path)).to_int()),
                      "colourfulness": colourfulness, "variant": variant,
                      "meanPixel": list(pixel), "tone": tone,
                      "mode": "light" if tone > 60 else "dark"})
    return cases


def theme_outputs(colours, mode):
    """Run apply_colours without touching terminals, Hyprland or running apps."""
    out = SANDBOX / "theme"
    shutil.rmtree(SANDBOX, ignore_errors=True)
    for var in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"):
        Path(os.environ[var]).mkdir(parents=True, exist_ok=True)
    user_templates = Path(os.environ["XDG_CONFIG_HOME"]) / "burl/templates"
    user_templates.mkdir(parents=True)
    (user_templates / "sample.txt").write_text(
        "fg={{ onSurface.hex }} bg={{ surface.rgb }} a={{ primary.hexalpha }} "
        "ra={{ primary.rgbalpha }} mode={{ mode }} bad={{ nope.hex }} raw={{ $primary }}\n")
    for client in ("Vencord",):
        (Path(os.environ["XDG_CONFIG_HOME"]) / client).mkdir()

    real_run = subprocess.run
    subprocess.run = lambda *a, **k: subprocess.CompletedProcess(a, 0, "", "")
    theme.apply_terms = lambda sequences: (Path(os.environ["XDG_STATE_HOME"]) / "burl").mkdir(
        parents=True, exist_ok=True) or (Path(os.environ["XDG_STATE_HOME"]) / "burl/sequences.txt").write_text(sequences)
    try:
        theme.apply_colours(colours, mode)
    finally:
        subprocess.run = real_run

    files = {}
    for base in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME"):
        root = Path(os.environ[base])
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.name != "theme.lock" and "burl/templates" not in str(path):
                files[f"{base}/{path.relative_to(root)}"] = path.read_text()
    return files


def main():
    scheme_cases = schemes()
    with tempfile.TemporaryDirectory() as tmp:
        images_dir = HERE / "images"
        images_dir.mkdir(exist_ok=True)
        cases = image_cases(Path(tmp))
        for path in Path(tmp).iterdir():
            shutil.copy(path, images_dir / path.name)

    themes = []
    for case in (scheme_cases[0], scheme_cases[3]):  # tonalspot light default, dark hard
        themes.append({"mode": case["mode"], "colours": case["colours"],
                       "files": theme_outputs(case["colours"], case["mode"])})

    (HERE / "schemes.json").write_text(json.dumps(scheme_cases, indent=1) + "\n")
    (HERE / "images.json").write_text(json.dumps(cases, indent=1) + "\n")
    (HERE / "themes.json").write_text(json.dumps(themes, indent=1) + "\n")
    shutil.rmtree(SANDBOX, ignore_errors=True)
    print(f"{len(scheme_cases)} schemes, {len(cases)} images, {len(themes)} theme runs")


if __name__ == "__main__":
    main()
