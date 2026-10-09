#!/usr/bin/env python3
"""Bake independently billowing cloud banks for Burl's three scenes."""
import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--scene', choices=['dream', 'tree', 'sky', 'veil'], required=True)
parser.add_argument('--frames', type=int, default=32)
parser.add_argument('--preview', action='store_true')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
args.output.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.eevee.taa_render_samples = 16
scene.eevee.volumetric_samples = 64
scene.eevee.volumetric_tile_size = '2'
scene.eevee.use_volume_custom_range = True
scene.eevee.volumetric_start = 8 if args.scene == 'dream' else 16
scene.eevee.volumetric_end = 45 if args.scene == 'dream' else 27
scene.eevee.use_volumetric_shadows = True
scene.render.threads_mode = 'FIXED'
scene.render.threads = 8
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.resolution_percentage = 75 if args.preview else 100
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
scene.world.color = (0.008, 0.012, 0.025)
scene.view_settings.view_transform = 'AgX'


def box(name, at, scale, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(mat)
    return ob


palettes = {
    'dream': [(0.06,0.32,0.45), (0.55,0.13,0.27), (0.42,0.38,0.24), (0.22,0.08,0.42)],
    'tree': [(0.12,0.31,0.36), (0.38,0.20,0.31), (0.32,0.35,0.40), (0.18,0.12,0.32)],
    'sky': [(0.05,0.15,0.35), (0.34,0.08,0.27), (0.08,0.31,0.38), (0.29,0.16,0.43)],
    'veil': [(0.43,0.53,0.56), (0.42,0.36,0.48), (0.37,0.47,0.49)],
}
# Camera-space banks leave the middle sky open and gather around the roots.
banks = {
    'tree': [(-6,1,-2,4,2,2), (5,2,-2.2,5,2,2.2), (-4,2,1.5,3,2,2.5), (5,3,3.2,4,2,2), (0,3,-3.4,5,2,1.3)],
    'veil': [(-5,-1,-3.3,4.5,1.5,1.3), (4,-1,-2.7,3.5,1.8,1.6), (-1,-1,-3.9,4,1.2,0.9), (-3,-1,0.0,2.3,1.0,0.65)],
    'sky': [(-6,2,3.2,5,2,2.4), (6,1,0.7,3.5,2,3), (-3,3,-3.4,5,2,1.5), (4,3,-3,4,2,1.4)],
    'dream': [(-8,5,5,5,3,4), (8,7,6,5,3,4), (-5,0,0,5,4,1.4), (5,3,0,4,5,1.4), (-5,12,2,5,3,3), (5,14,4,5,3,4), (0,-7,-0.4,7,2,0.9)],
}
animated = []
for index, (x,y,z,sx,sy,sz) in enumerate(banks[args.scene]):
    mat = bpy.data.materials.new(f'Cloud bank {index}')
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    def node(kind):
        return nodes.new(kind)
    def calc(operation, a, b):
        item = node('ShaderNodeMath')
        item.operation = operation
        for i, value in enumerate([a,b]):
            if isinstance(value, (int,float)): item.inputs[i].default_value = value
            else: links.new(value,item.inputs[i])
        return item.outputs[0]
    tex = node('ShaderNodeTexCoord')
    center = node('ShaderNodeVectorMath'); center.operation = 'SUBTRACT'
    links.new(tex.outputs['Generated'],center.inputs[0]); center.inputs[1].default_value = (.5,.5,.5)
    length = node('ShaderNodeVectorMath'); length.operation = 'LENGTH'
    links.new(center.outputs[0],length.inputs[0])
    envelope = node('ShaderNodeMapRange')
    links.new(length.outputs['Value'],envelope.inputs['Value'])
    envelope.inputs['From Min'].default_value=.25
    envelope.inputs['From Max'].default_value=.5
    envelope.inputs['To Min'].default_value=1
    envelope.inputs['To Max'].default_value=0
    envelope.interpolation_type='SMOOTHERSTEP'
    offset = node('ShaderNodeVectorMath'); offset.operation='ADD'
    links.new(tex.outputs['Generated'],offset.inputs[0])
    noise = node('ShaderNodeTexNoise'); noise.noise_dimensions='4D'
    links.new(offset.outputs[0],noise.inputs['Vector'])
    noise.inputs['Scale'].default_value=3.4
    noise.inputs['Detail'].default_value=5
    noise.inputs['Roughness'].default_value=.72
    noise.inputs['Distortion'].default_value=.25
    noise.inputs['W'].default_value=index*2.37
    ramp=node('ShaderNodeMapRange')
    links.new(noise.outputs['Fac'],ramp.inputs['Value'])
    ramp.inputs['From Min'].default_value=.53
    ramp.inputs['From Max'].default_value=.72
    ramp.inputs['To Min'].default_value=0
    ramp.inputs['To Max'].default_value=9 if args.scene=='veil' else 7
    ramp.interpolation_type='SMOOTHERSTEP'
    density=calc('MULTIPLY',ramp.outputs['Result'],envelope.outputs['Result'])
    volume=node('ShaderNodeVolumePrincipled')
    colour=palettes[args.scene][index % len(palettes[args.scene])]
    volume.inputs['Color'].default_value=(*colour,1)
    links.new(density,volume.inputs['Density'])
    volume.inputs['Emission Color'].default_value=(*colour,1)
    links.new(calc('MULTIPLY',density,.08 if args.scene=='veil' else .18),volume.inputs['Emission Strength'])
    volume.inputs['Anisotropy'].default_value=.25
    output=node('ShaderNodeOutputMaterial'); links.new(volume.outputs[0],output.inputs['Volume'])
    cloud=box(f'Cloud bank {index}',(x,y,z),(sx*2,sy*2,sz*2),mat)
    animated.append((offset,noise,cloud,(x,y,z)))


for location, colour, energy in [((-5,-3,7),(.4,.8,1),2400),((5,1,7),(1,.55,.38),3000),((0,12,6),(.7,.65,1),4000)]:
    bpy.ops.object.light_add(type='AREA',location=location)
    lamp=bpy.context.object
    lamp.data.energy=energy
    lamp.data.color=colour
    lamp.data.shape='DISK'; lamp.data.size=7
    lamp.rotation_euler=(Vector((0,4,1))-lamp.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(0,-21,7) if args.scene=='dream' else (0,-20,0))
camera=bpy.context.object
camera.rotation_euler=(Vector((0,5,2.8) if args.scene=='dream' else (0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
if args.scene!='dream':
    camera.data.type='ORTHO'; camera.data.ortho_scale=17
else: camera.data.lens=28
scene.camera=camera
scene.frame_start=1; scene.frame_end=args.frames
for frame in range(args.frames+1):
    phase=math.tau*frame/args.frames
    for i,(offset,noise,cloud,origin) in enumerate(animated):
        t=phase+i*1.71
        offset.inputs[1].default_value=(.07*math.cos(t),.09*math.sin(t),.04*math.sin(t))
        offset.inputs[1].keyframe_insert('default_value',frame=frame+1)
        noise.inputs['W'].default_value=i*2.37+.12*math.sin(t)
        noise.inputs['W'].keyframe_insert('default_value',frame=frame+1)
        cloud.location=(origin[0]+.18*math.sin(t),origin[1],origin[2]+.08*math.cos(t))
        cloud.keyframe_insert('location',frame=frame+1)
scene.render.fps=1
bpy.ops.wm.save_as_mainfile(filepath=str(args.output/(args.scene+'.blend')))
for frame in range(1,2 if args.preview else args.frames+1):
    scene.frame_set(frame)
    scene.render.filepath=str(args.output/f'{args.scene}-{frame:03d}.png')
    bpy.ops.render.render(write_still=True)
