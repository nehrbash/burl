"""Build a wood-constrained arrival texture with Blender's image API."""

import argparse
from collections import deque
import heapq
import json
import math
from pathlib import Path
import sys

import bpy
import numpy as np


NEIGHBORS = tuple((dx, dy, math.hypot(dx, dy))
                  for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dx or dy)
ORB_ANCHORS = [(0.2545, 0.2072), (0.646, 0.2132), (0.686, 0.3894),
               (0.1648, 0.407), (0.82, 0.5273), (0.2115, 0.5926)]
ROOT_ANCHORS = [(0.17, 0.87), (0.285, 0.925), (0.41, 0.947),
                (0.59, 0.938), (0.73, 0.91), (0.855, 0.865)]


def pixels(image):
    values = np.empty(image.size[0] * image.size[1] * 4, dtype=np.float32)
    image.pixels.foreach_get(values)
    return values.reshape(image.size[1], image.size[0], 4)[::-1].copy()


def save_image(path, rgba):
    height, width = rgba.shape[:2]
    image = bpy.data.images.new(Path(path).stem, width=width, height=height, alpha=True)
    image.colorspace_settings.name = 'Non-Color'
    image.pixels.foreach_set(np.ascontiguousarray(rgba[::-1]).ravel())
    image.filepath_raw = str(Path(path).resolve())
    image.file_format = 'PNG'
    image.save()
    bpy.data.images.remove(image)


def nearest_wood(alpha, u, v):
    yy, xx = np.nonzero(alpha >= 0.35)
    if not len(xx):
        raise ValueError('Source contains no opaque wood')
    target_x, target_y = u * (alpha.shape[1] - 1), v * (alpha.shape[0] - 1)
    index = np.argmin((xx - target_x) ** 2 + (yy - target_y) ** 2)
    return int(xx[index]), int(yy[index])


def wood_distance(alpha, seed):
    height, width = alpha.shape
    distance = np.full((height, width), np.inf, dtype=np.float64)
    predecessor = np.full((height, width), -1, dtype=np.int32)
    cost = 1.0 / np.maximum(alpha, 0.035) ** 0.65
    cost[alpha < 0.015] = 1000.0
    sx, sy = seed
    distance[sy, sx] = 0
    pending = [(0.0, sx, sy)]
    while pending:
        current, x, y = heapq.heappop(pending)
        if current != distance[y, x]:
            continue
        for dx, dy, step in NEIGHBORS:
            nx, ny = x + dx, y + dy
            if not (0 <= nx < width and 0 <= ny < height):
                continue
            candidate = current + step * (cost[y, x] + cost[ny, nx]) * 0.5
            if candidate < distance[ny, nx]:
                distance[ny, nx] = candidate
                predecessor[ny, nx] = y * width + x
                heapq.heappush(pending, (candidate, nx, ny))
    return distance, predecessor


def extend_edges(arrival, visible, radius=6):
    height, width = arrival.shape
    steps = np.full((height, width), -1, dtype=np.int16)
    steps[visible] = 0
    ys, xs = np.nonzero(visible)
    pending = deque(zip(xs.tolist(), ys.tolist()))
    result = np.where(visible, arrival, 1.0)
    while pending:
        x, y = pending.popleft()
        if steps[y, x] >= radius:
            continue
        for dx, dy, _ in NEIGHBORS:
            nx, ny = x + dx, y + dy
            if 0 <= nx < width and 0 <= ny < height and steps[ny, nx] < 0:
                steps[ny, nx] = steps[y, x] + 1
                result[ny, nx] = result[y, x]
                pending.append((nx, ny))
    return result


def anchor_metadata(alpha, arrival, anchors):
    result = []
    height, width = alpha.shape
    for u, v in anchors:
        x, y = nearest_wood(alpha, u, v)
        result.append({'anchor': [u, v], 'wood': [x / (width - 1), y / (height - 1)],
                       'arrival': float(arrival[y, x])})
    return result


def trace_routes(alpha, distance, predecessor, normalizer, anchors, connectors):
    height, width = alpha.shape
    routes = []
    for u, v in anchors:
        x, y = nearest_wood(alpha, u, v)
        wood = [x / (width - 1), y / (height - 1)]
        nodes = []
        while True:
            nodes.append([x / (width - 1), y / (height - 1), float(distance[y, x])])
            previous = predecessor[y, x]
            if previous < 0:
                break
            y, x = divmod(int(previous), width)
        nodes.reverse()
        nodes = nodes[::2] + ([nodes[-1]] if (len(nodes) - 1) % 2 else [])
        if connectors:
            gap = math.hypot((wood[0] - u) * width, (wood[1] - v) * height)
            nodes.append([u, v, nodes[-1][2] + gap])
        length = max(nodes[-1][2], 1.0)
        routes.append({'arrival': round(min(length / normalizer, 1.0), 6),
                       'wood': [round(value, 6) for value in wood],
                       'points': [[round(px, 6), round(py, 6), round(t / length, 6)]
                                  for px, py, t in nodes]})
    return routes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--diagnostic', type=Path)
    parser.add_argument('--paths', type=Path)
    parser.add_argument('--width', type=int, default=512)
    parser.add_argument('--seed-u', type=float, default=0.50)
    parser.add_argument('--seed-v', type=float, default=0.91)
    arguments = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    args = parser.parse_args(arguments)
    if args.source.resolve() == args.output.resolve():
        parser.error('Source and output must be different files')
    if args.width < 32:
        parser.error('Width must be at least 32')
    source = bpy.data.images.load(str(args.source.resolve()), check_existing=False)
    source.colorspace_settings.name = 'Non-Color'
    source_size = list(source.size)
    height = round(source.size[1] * args.width / source.size[0])
    source.scale(args.width, height)
    rgba = pixels(source)
    alpha = rgba[:, :, 3]
    seed = nearest_wood(alpha, args.seed_u, args.seed_v)
    distance, predecessor = wood_distance(alpha, seed)
    # Detached antialias flecks must not stretch the entire tree's growth duration.
    normalizer = float(np.percentile(distance[alpha >= 0.35], 99.5))
    arrival = np.clip(distance / max(normalizer, 1.0), 0, 1)
    extended = extend_edges(arrival, alpha >= 0.015)
    mask = np.ones((height, args.width, 4), dtype=np.float32)
    mask[:, :, :3] = extended[:, :, None]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    save_image(args.output, mask)
    metadata = {'source': str(args.source), 'source_size': source_size,
                'mask_size': [args.width, height], 'origin': 'top-left',
                'channels': 'RGB arrival, opaque alpha; linear data',
                'seed_uv': [seed[0] / (args.width - 1), seed[1] / (height - 1)],
                'distance_normalizer': normalizer,
                'orbs': anchor_metadata(alpha, arrival, ORB_ANCHORS),
                'roots': anchor_metadata(alpha, arrival, ROOT_ANCHORS)}
    if args.paths:
        routes = {'orbs': trace_routes(alpha, distance, predecessor, normalizer, ORB_ANCHORS, True),
                  'roots': trace_routes(alpha, distance, predecessor, normalizer, ROOT_ANCHORS, False)}
        args.paths.parent.mkdir(parents=True, exist_ok=True)
        args.paths.write_text('.pragma library\n\n'
                              + ''.join('var ' + key + ' = ' + json.dumps(value, separators=(',', ':'))
                                        + ';\n' for key, value in routes.items()))
    args.output.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n')
    if args.diagnostic:
        panels = []
        for progress in (0.25, 0.50, 0.75, 1.0):
            revealed = np.clip((progress - arrival + 0.025) / 0.05, 0, 1)
            if progress == 1.0:
                revealed[:] = 1
            opacity = alpha * revealed
            panel = np.ones_like(rgba)
            panel[:, :, :3] = (rgba[:, :, :3] * opacity[:, :, None]
                                + np.array([0.055, 0.042, 0.033]) * (1 - opacity[:, :, None]))
            panels.append(panel)
        save_image(args.diagnostic, np.concatenate(panels, axis=1))
    print(json.dumps(metadata))


if __name__ == '__main__':
    main()
