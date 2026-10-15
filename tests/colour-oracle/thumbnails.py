#!/usr/bin/env python3
"""Freeze Pillow's wallpaper thumbnails (burl.utils.wallpaper.get_thumb) as fixtures for the C++ port.

Run from the burl checkout with Pillow available; only tests/colour-oracle/thumbnails/ is written:
    python3 tests/colour-oracle/thumbnails.py
"""
import json
import random
import shutil
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE / "thumbnails"


def noisy_gradient(width, height, rng, amplitude):
    image = Image.new("RGB", (width, height))
    image.putdata([
        (min(255, (x * 255 // width) + rng.randrange(amplitude)),
         min(255, (y * 255 // height) + rng.randrange(amplitude)),
         min(255, 255 - (x * 255 // width) + rng.randrange(amplitude)))
        for y in range(height) for x in range(width)])
    return image


def blocks(width, height, size):
    palette = [(200, 40, 40), (30, 140, 60), (240, 200, 40), (20, 20, 30), (230, 230, 240)]
    image = Image.new("RGB", (width, height))
    image.putdata([palette[(x // size + y // size) % len(palette)] for y in range(height) for x in range(width)])
    return image


def sources():
    rng = random.Random(20261015)
    yield "hd-gradient-noise.jpg", noisy_gradient(1920, 1080, rng, 24), {"quality": 60, "comment": b"burl fixture"}
    yield "portrait-blocks.png", blocks(1000, 3000, 37), {}
    alpha = Image.new("RGBA", (333, 129))
    alpha.putdata([(x * 255 // 333, 100, y * 255 // 129, (x + y) * 255 // 462) for y in range(129) for x in range(333)])
    yield "alpha-333x129.png", alpha, {}
    yield "ultrawide-blocks.png", blocks(4000, 30, 11), {}
    yield "sliver-blocks.png", blocks(10, 1500, 3), {}
    yield "near-square.png", noisy_gradient(129, 127, rng, 40), {}
    yield "exact-box.png", noisy_gradient(128, 128, rng, 40), {}
    yield "small.png", noisy_gradient(90, 60, rng, 40), {}
    yield "odd-prime.jpg", noisy_gradient(1013, 607, rng, 30), {"quality": 85}
    yield "photo.webp", noisy_gradient(800, 450, rng, 20), {"quality": 80}


def thumbnail(path, thumb):
    # Mirrors burl.utils.wallpaper.get_thumb.
    with Image.open(path) as img:
        img = img.convert("RGB")
        img.thumbnail((128, 128), Image.NEAREST)
        img.save(thumb, "JPEG")


def main():
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir()
    cases = []
    for name, image, options in sources():
        path = OUT / name
        image.save(path, **options)
        thumb = OUT / (path.stem + ".thumb.jpg")
        thumbnail(path, thumb)
        cases.append({"source": name, "thumbnail": thumb.name})
    (OUT / "thumbnails.json").write_text(json.dumps(cases, indent=1) + "\n")
    print(f"{len(cases)} thumbnails")


if __name__ == "__main__":
    main()
