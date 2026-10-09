#!/usr/bin/env python3
"""Build and render an editable Blender scene for painted tree growth."""

import argparse
import sys
from pathlib import Path

import bpy


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--art", type=Path, required=True)
    parser.add_argument("--growth-map", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--size", default="512x380")
    parser.add_argument("--frames", type=int, default=48)
    parser.add_argument("--samples", type=int, default=32)
    parser.add_argument("--preview", type=int, default=0)
    parser.add_argument("--no-render", action="store_true")
    parser.add_argument("--blend", type=Path, default=Path(__file__).resolve().parents[1] / "assets/world-tree-source/world-tree-layer.blend")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])


def material_for(art_path, growth_path, frames):
    material = bpy.data.materials.new("Painted heartwood · geodesic growth")
    material.use_nodes = True
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    material.use_backface_culling = False
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    art = nodes.new("ShaderNodeTexImage")
    art.name = "Original painted tree"
    art.label = "Original painted tree · sRGB + alpha"
    art.location = (-900, 240)
    art.image = bpy.data.images.load(str(art_path.resolve()))
    art.image.pack()
    art.extension = "CLIP"
    arrival = nodes.new("ShaderNodeTexImage")
    arrival.name = "Growth arrival map"
    arrival.label = "Geodesic arrival · linear data"
    arrival.location = (-900, -90)
    arrival.image = bpy.data.images.load(str(growth_path.resolve()))
    arrival.image.colorspace_settings.name = "Non-Color"
    arrival.image.pack()
    arrival.extension = "EXTEND"
    threshold = nodes.new("ShaderNodeValue")
    threshold.name = "Growth threshold"
    threshold.label = "Animated emergence"
    threshold.location = (-900, -380)
    threshold.outputs[0].default_value = -0.02
    threshold.outputs[0].keyframe_insert(data_path="default_value", frame=1)
    threshold.outputs[0].default_value = 1.02
    threshold.outputs[0].keyframe_insert(data_path="default_value", frame=frames)

    difference = nodes.new("ShaderNodeMath")
    difference.operation = "SUBTRACT"
    difference.location = (-610, -90)
    links.new(threshold.outputs[0], difference.inputs[0])
    links.new(arrival.outputs["Color"], difference.inputs[1])
    reveal = nodes.new("ShaderNodeMapRange")
    reveal.interpolation_type = "SMOOTHERSTEP"
    reveal.clamp = True
    reveal.location = (-390, -50)
    reveal.inputs["From Min"].default_value = -0.014
    reveal.inputs["From Max"].default_value = 0.014
    links.new(difference.outputs[0], reveal.inputs["Value"])
    alpha = nodes.new("ShaderNodeMath")
    alpha.operation = "MULTIPLY"
    alpha.location = (-130, 30)
    links.new(art.outputs["Alpha"], alpha.inputs[0])
    links.new(reveal.outputs["Result"], alpha.inputs[1])

    edge_distance = nodes.new("ShaderNodeMath")
    edge_distance.operation = "ABSOLUTE"
    edge_distance.location = (-390, -340)
    links.new(difference.outputs[0], edge_distance.inputs[0])
    edge = nodes.new("ShaderNodeMapRange")
    edge.interpolation_type = "SMOOTHSTEP"
    edge.clamp = True
    edge.location = (-160, -310)
    edge.inputs["From Min"].default_value = 0
    edge.inputs["From Max"].default_value = 0.022
    edge.inputs["To Min"].default_value = 0.12
    edge.inputs["To Max"].default_value = 0
    links.new(edge_distance.outputs[0], edge.inputs["Value"])
    light = nodes.new("ShaderNodeMixRGB")
    light.blend_type = "ADD"
    light.location = (100, 250)
    light.inputs[2].default_value = (0.85, 0.57, 0.23, 1)
    links.new(edge.outputs["Result"], light.inputs[0])
    links.new(art.outputs["Color"], light.inputs[1])
    emission = nodes.new("ShaderNodeEmission")
    emission.location = (330, 240)
    emission.inputs["Strength"].default_value = 1
    links.new(light.outputs[0], emission.inputs["Color"])
    transparent = nodes.new("ShaderNodeBsdfTransparent")
    transparent.location = (330, 80)
    blend = nodes.new("ShaderNodeMixShader")
    blend.location = (560, 180)
    links.new(alpha.outputs[0], blend.inputs[0])
    links.new(transparent.outputs[0], blend.inputs[1])
    links.new(emission.outputs[0], blend.inputs[2])
    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (780, 180)
    links.new(blend.outputs[0], output.inputs["Surface"])
    return material


def build(args):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.eevee.taa_render_samples = args.samples
    scene.render.resolution_x, scene.render.resolution_y = map(int, args.size.lower().split("x"))
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = args.frames
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    scene.world.color = (0, 0, 0)
    aspect = scene.render.resolution_x / scene.render.resolution_y
    bpy.ops.mesh.primitive_plane_add(size=2)
    plane = bpy.context.object
    plane.name = "World tree · painted growth layer"
    plane.scale = (aspect, 1, 1)
    plane.data.materials.append(material_for(args.art, args.growth_map, args.frames))
    camera_data = bpy.data.cameras.new("Illustration camera")
    camera = bpy.data.objects.new("Illustration camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0, 0, 5)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 2 * max(1, aspect)
    scene.camera = camera
    scene["generator"] = "scripts/render-tree-layer.py"
    scene["growth_method"] = "Geodesic arrival along the painted alpha silhouette"
    scene.frame_set(args.frames)
    args.blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(args.blend.resolve()))
    return scene


def main():
    args = arguments()
    if args.frames < 2:
        raise ValueError("--frames must be at least 2")
    scene = build(args)
    if args.no_render:
        return
    args.output.mkdir(parents=True, exist_ok=True)
    if args.preview:
        scene.frame_set(args.preview)
        scene.render.filepath = str(args.output / f"growth-{args.preview:04}.png")
        bpy.ops.render.render(write_still=True)
    else:
        scene.render.filepath = str(args.output / "growth-")
        bpy.ops.render.render(animation=True)


if __name__ == "__main__":
    main()
