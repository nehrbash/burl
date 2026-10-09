#!/usr/bin/env python3
"""Run with Blender: blender -b --python render-world-tree.py -- --output /tmp/world-tree."""

import argparse
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--size", default="1200x1000")
    parser.add_argument("--frames", type=int, default=0)
    parser.add_argument("--preview", type=int, default=0, help="Render a growth frame instead of the final frame")
    parser.add_argument("--samples", type=int, default=48)
    parser.add_argument("--engine", choices=("eevee", "cycles"), default="eevee")
    parser.add_argument("--seed", type=int, default=719)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])


def colour(hex_value):
    values = [int(hex_value[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(v / 12.92 if v < 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in values) + (1,)


def wood_material():
    material = bpy.data.materials.new("Smoked walnut · antique gold ridges")
    material.diffuse_color = colour("6b5040")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    surface = nodes.get("Principled BSDF")
    surface.inputs["Roughness"].default_value = 0.88
    surface.inputs["Metallic"].default_value = 0.0
    coordinates = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeVectorMath")
    mapping.operation = "MULTIPLY"
    mapping.inputs[1].default_value = (8, 8, 0.8)
    links.new(coordinates.outputs["Generated"], mapping.inputs[0])
    grain = nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 7.5
    grain.inputs["Detail"].default_value = 5
    grain.inputs["Roughness"].default_value = 0.72
    links.new(mapping.outputs[0], grain.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.22
    ramp.color_ramp.elements[0].color = colour("211914")
    ramp.color_ramp.elements[1].position = 0.82
    ramp.color_ramp.elements[1].color = colour("987657")
    middle = ramp.color_ramp.elements.new(0.48)
    middle.color = colour("574131")
    links.new(grain.outputs["Fac"], ramp.inputs[0])
    links.new(ramp.outputs[0], surface.inputs["Base Color"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.3
    bump.inputs["Distance"].default_value = 0.06
    links.new(grain.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], surface.inputs["Normal"])
    texture_dir = Path(__file__).resolve().parents[1] / "assets" / "world-tree-source"
    if (texture_dir / "bark_brown_01_diff_1k.jpg").exists():
        for kind, socket in (("diff", "Base Color"), ("rough", "Roughness"), ("nor_gl", None)):
            image = nodes.new("ShaderNodeTexImage")
            image.image = bpy.data.images.load(str(texture_dir / f"bark_brown_01_{kind}_1k.jpg"))
            image.image.pack()
            image.extension = "REPEAT"
            if kind != "diff":
                image.image.colorspace_settings.name = "Non-Color"
            if kind == "nor_gl":
                normal = nodes.new("ShaderNodeNormalMap")
                normal.inputs["Strength"].default_value = 0.8
                links.new(image.outputs["Color"], normal.inputs["Color"])
                links.new(normal.outputs["Normal"], bump.inputs["Normal"])
            elif kind == "diff":
                tint = nodes.new("ShaderNodeMixRGB")
                tint.blend_type = "MULTIPLY"
                tint.inputs[0].default_value = 0.63
                tint.inputs[2].default_value = colour("6b5040")
                links.new(image.outputs["Color"], tint.inputs[1])
                links.new(tint.outputs[0], surface.inputs[socket])
            else:
                links.new(image.outputs["Color"], surface.inputs[socket])
    return material


def catmull(points, t):
    at = min(len(points) - 1.000001, max(0, t) * (len(points) - 1))
    index = int(at)
    fraction = at - index
    p0 = points[max(0, index - 1)]
    p1 = points[index]
    p2 = points[min(len(points) - 1, index + 1)]
    p3 = points[min(len(points) - 1, index + 2)]
    return 0.5 * ((2 * p1) + (-p0 + p2) * fraction
                  + (2 * p0 - 5 * p1 + 4 * p2 - p3) * fraction ** 2
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * fraction ** 3)


class Tree:
    def __init__(self, material, seed, duration):
        self.material = material
        self.random = random.Random(seed)
        self.duration = duration
        self.branches = []

    def limb(self, name, points, radius, start, finish, taper=1.05, flutes=7):
        points = [Vector(point) for point in points]
        ring_count = 54 if radius > 0.35 else 32 if radius > 0.10 else 20
        sides = 28 if radius > 0.35 else 16 if radius > 0.08 else 8
        phase = self.random.uniform(0, 2 * math.pi)
        centers = [catmull(points, i / (ring_count - 1)) for i in range(ring_count)]
        faces = []
        for ring in range(ring_count - 1):
            for side in range(sides):
                a = ring * sides + side
                b = ring * sides + (side + 1) % sides
                faces.append((a, b, b + sides, a + sides))
        faces.extend([tuple(reversed(range(sides))), tuple((ring_count - 1) * sides + i for i in range(sides))])

        def vertices(growth):
            result = []
            for ring in range(ring_count):
                t = ring / (ring_count - 1)
                clipped = min(t, growth)
                center = catmull(points, clipped)
                tangent = (catmull(points, min(1, clipped + 0.002)) - catmull(points, max(0, clipped - 0.002))).normalized()
                axis = tangent.cross(Vector((0, 1, 0))).normalized()
                normal = tangent.cross(axis).normalized()
                tip = max(0.002, min(1, (growth - t) * 16))
                thickness = radius * max(0.004, (1 - t) ** taper) * tip
                swell = 1 + 0.12 * math.sin(t * 13 + phase) + 0.045 * math.sin(t * 39 + phase)
                for side in range(sides):
                    theta = 2 * math.pi * side / sides
                    ridge = 1 + 0.16 * math.cos(theta * flutes + t * 5 + phase)
                    ridge += 0.065 * math.cos(theta * (flutes + 3) - t * 11)
                    angle = theta + t * 0.6
                    offset = axis * math.cos(angle) + normal * math.sin(angle)
                    result.append(tuple(center + offset * thickness * ridge * swell))
            return result

        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(vertices(0), [], faces)
        mesh.materials.append(self.material)
        mesh.update()
        uv = mesh.uv_layers.new(name="Bark cylinder")
        length = sum((b - a).length for a, b in zip(centers, centers[1:]))
        for polygon in mesh.polygons:
            wraps = any(mesh.loops[i].vertex_index % sides == sides - 1 for i in polygon.loop_indices)
            for loop_index in polygon.loop_indices:
                vertex = mesh.loops[loop_index].vertex_index
                side = vertex % sides
                u = 1 if wraps and side == 0 else side / sides
                v = (vertex // sides) / (ring_count - 1)
                uv.data[loop_index].uv = (u * max(0.25, radius * 8), v * length * 0.75)

        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        obj.shape_key_add(name="Dormant")
        obj.data.shape_keys.use_relative = False
        for stage in range(1, 9):
            key = obj.shape_key_add(name=f"Growth {stage}/8")
            for vertex, co in zip(key.data, vertices(stage / 8)):
                vertex.co = co
            key.interpolation = "KEY_LINEAR"
        keys = obj.data.shape_keys
        keys.eval_time = 0
        keys.keyframe_insert(data_path="eval_time", frame=max(1, start * self.duration))
        keys.eval_time = keys.key_blocks[-1].frame
        keys.keyframe_insert(data_path="eval_time", frame=max(2, finish * self.duration))
        obj["growth_start"] = start
        obj["growth_finish"] = finish
        obj["branch_points"] = [tuple(point) for point in points]
        self.branches.append(obj)
        return points

    def twigs(self, points, radius, start, finish, side, level=0):
        count = self.random.randint(4, 6) if level == 0 else self.random.randint(2, 4)
        positions = sorted(self.random.uniform(0.28, 0.89) for _ in range(count))
        for i, t in enumerate(positions):
            anchor = catmull(points, t)
            tangent = (catmull(points, min(1, t + 0.025)) - anchor).normalized()
            parent_angle = math.atan2(tangent.z, tangent.x)
            turn = self.random.uniform(0.42, 1.2) * (-1 if i % 2 else 1)
            angle = parent_angle + turn
            length = self.random.uniform(1.0, 2.25) if level == 0 else self.random.uniform(0.4, 1.0)
            path = [anchor]
            for segment in range(4):
                angle += self.random.uniform(-0.42, 0.42)
                offset = Vector((math.cos(angle), self.random.uniform(-0.25, 0.25), math.sin(angle))) * length / 4
                point = path[-1] + offset
                point.x = max(-7.05, min(7.05, point.x))
                point.z = min(11.9, point.z)
                path.append(point)
            delay = start + (finish - start) * t
            twig_finish = min(1, delay + (0.25 if level == 0 else 0.14))
            child_radius = radius * (1 - t) ** 0.85 * self.random.uniform(0.38, 0.6)
            child = self.limb(f"Twig {level}.{len(self.branches):03}", path,
                              child_radius, delay, twig_finish, taper=1.35, flutes=5)
            if level < 1:
                self.twigs(child, child_radius, delay, twig_finish, side, level + 1)

    def build(self):
        self.limb("Heartwood trunk", [(0, 0, -0.3), (-0.20, 0.03, 1.2), (0.16, 0, 2.7),
                   (-0.20, 0.10, 4.0), (0.10, 0.05, 5.3), (1.35, 0.2, 5.3), (2.15, 0.25, 6.3)],
                  0.86, 0, 0.43, taper=0.75, flutes=11)
        self.limb("Twined heartwood", [(0.37, 0.10, 0), (0.50, 0.16, 1.2), (0.03, -0.20, 2.7),
                   (-0.45, -0.12, 4.0), (-1.12, 0.2, 5.0), (-1.85, 0.15, 6.4)],
                  0.59, 0.01, 0.44, taper=0.9, flutes=9)
        paths = [
            [(-0.10, 0.04, 2.6), (-1.02, 0.0, 3.8), (-2.3, 0.1, 4.1), (-3.8, 0.1, 4.5), (-5.25, 0.2, 5.6), (-6.0, 0.1, 4.95)],
            [(0.18, 0.18, 3.1), (1.02, 0.2, 3.9), (2.35, 0, 4.35), (3.1, 0, 5.3), (4.85, 0.1, 5.5), (5.65, 0.3, 5.9)],
            [(-0.12, 0.12, 4.0), (-1.12, 0.2, 5.0), (-1.85, 0.15, 6.4), (-3.3, 0.1, 7.25), (-4.8, 0.2, 7.45), (-5.5, 0.1, 7.75)],
            [(0.1, 0.08, 4.7), (1.35, 0.2, 5.3), (2.15, 0.25, 6.3), (3.1, 0.1, 7.0), (4.95, 0.1, 7.25), (6.1, 0.1, 8.9)],
            [(-0.08, 0.08, 5.3), (-0.9, -0.03, 6.4), (-1.4, 0.12, 7.9), (-2.6, 0.1, 8.9), (-3.55, 0.1, 10.1), (-4.2, 0.05, 10.45)],
            [(0.20, 0.1, 5.95), (1.3, 0.1, 6.9), (1.8, 0.15, 8.3), (3.1, 0.2, 9.25), (4.0, 0.12, 10.5), (4.0, 0.12, 10.75)],
            [(0.10, 0.05, 4.9), (0.75, 0.12, 5.9), (0.36, 0.02, 7.0), (1.0, -0.18, 8.1), (0.9, 0.08, 9.4), (1.85, 0.15, 10.4), (2.35, 0.2, 11.65)],
            [(-0.30, 0.1, 4.4), (-0.55, 0.13, 5.5), (-0.49, 0.15, 6.8), (-1.12, 0.13, 8.0), (-1.0, 0.05, 9.2), (-1.85, 0.0, 10.25), (-2.05, 0.12, 11.5)],
        ]
        for i, path in enumerate(paths):
            start = 0.10 + path[0][2] / 11.4 * 0.39
            finish = min(0.87, start + 0.39)
            radius = [0.44, 0.45, 0.49, 0.46, 0.42, 0.41, 0.41, 0.36][i]
            points = self.limb(f"Bough {i + 1:02}", path, radius, start, finish, taper=1.65)
            self.twigs(points, radius, start, finish, -1 if path[-1][0] < 0 else 1)
        for i in range(11):
            side = -1 if i % 2 else 1
            reach = self.random.uniform(1.9, 4.4)
            depth = self.random.uniform(-0.50, 0.35)
            self.limb(f"Buttress root {i + 1:02}", [(side * 0.12, depth * 0.3, 1.25),
                      (side * 0.55, depth, 0.52), (side * reach * 0.43, depth, 0.12),
                      (side * reach * 0.75, depth + 0.2, 0.07), (side * reach, depth + 0.3, -0.12)],
                      self.random.uniform(0.19, 0.36), 0, 0.25, taper=1.35)


def point_at(obj, location):
    obj.rotation_euler = (Vector(location) - obj.location).to_track_quat("-Z", "Y").to_euler()


def area_light(name, location, energy, tint, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = tint
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    point_at(obj, (0, 0, 5.8))


def setup(args):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES" if args.engine == "cycles" else "BLENDER_EEVEE_NEXT"
    if args.engine == "cycles":
        scene.cycles.samples = args.samples
        scene.cycles.use_denoising = True
    if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = args.samples
    scene.render.resolution_x, scene.render.resolution_y = map(int, args.size.lower().split("x"))
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = args.frames or 48
    scene.world.color = (0.018, 0.015, 0.012)
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.exposure = -0.15
    material = wood_material()
    tree = Tree(material, args.seed, scene.frame_end)
    tree.build()
    data = bpy.data.cameras.new("Portrait orthographic")
    camera = bpy.data.objects.new("Portrait orthographic", data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0, -25, 6.0)
    point_at(camera, (0, 0, 6.0))
    data.type = "ORTHO"
    data.ortho_scale = 15.2
    scene.camera = camera
    area_light("Soft amber key", (-6, -9, 12), 950, (0.88, 0.82, 0.72), 7)
    area_light("Old gold rim", (5, 3, 10), 1400, (1.0, 0.72, 0.40), 5)
    area_light("Cool shadow lift", (3, -7, 6), 300, (0.58, 0.63, 0.67), 7)
    area_light("Root bounce", (-2, -4, 1), 120, (0.65, 0.49, 0.27), 3)
    scene["generator"] = "scripts/render-world-tree.py"
    scene["seed"] = args.seed
    return scene


def main():
    args = arguments()
    args.output.mkdir(parents=True, exist_ok=True)
    scene = setup(args)
    scene.frame_set(scene.frame_end)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output / "world-tree.blend"))
    scene.frame_set(args.preview or scene.frame_end)
    scene.render.filepath = str(args.output / (f"preview-{args.preview:04}.png" if args.preview else "world-tree.png"))
    bpy.ops.render.render(write_still=True)
    if args.frames:
        frames = args.output / "frames"
        frames.mkdir(exist_ok=True)
        scene.render.filepath = str(frames / "tree-")
        scene.frame_end = args.frames
        bpy.ops.render.render(animation=True)


if __name__ == "__main__":
    main()
