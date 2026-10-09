#!/usr/bin/env python3
"""Render the Burl book and opening sequence from an editable Blender scene."""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--blend', type=Path, required=True)
parser.add_argument('--frames', type=int, default=25)
parser.add_argument('--preview', action='store_true')
parser.add_argument('--no-render', action='store_true')
parser.add_argument('--scale', type=int, default=100)
parser.add_argument('--variant', choices=['dashboard', 'media', 'performance', 'weather', 'tasks'], default='dashboard')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
args.output.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32 if args.preview else 48
scene.cycles.use_denoising = True
scene.render.threads_mode = 'FIXED'
scene.render.threads = 8
scene.render.resolution_x = 1440
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 70 if args.preview else args.scale
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.world.color = (0.22, 0.22, 0.22)
scene.view_settings.view_transform = 'AgX'


def material(name, color, roughness, metallic=0, grain=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Metallic'].default_value = metallic
    if grain:
        noise = nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = grain
        noise.inputs['Detail'].default_value = 3
        bump = nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = 0.16
        bump.inputs['Distance'].default_value = 0.003 if grain > 100 else 0.014
        links.new(noise.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], shader.inputs['Normal'])
        ramp = nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].color = (*(c * 0.58 for c in color), 1)
        ramp.color_ramp.elements[1].color = (*(c * (1.06 if grain > 100 else 1.18) for c in color), 1)
        links.new(noise.outputs['Fac'], ramp.inputs[0])
        links.new(ramp.outputs[0], shader.inputs['Base Color'])
        stains = nodes.new('ShaderNodeTexNoise')
        stains.inputs['Scale'].default_value = 5
        stains.inputs['Detail'].default_value = 5
        weathering = nodes.new('ShaderNodeValToRGB')
        weathering.color_ramp.elements[0].position = 0.28
        weathering.color_ramp.elements[0].color = (0.18, 0.13, 0.09, 1)
        weathering.color_ramp.elements[1].position = 0.67
        weathering.color_ramp.elements[1].color = (1, 0.91, 0.75, 1)
        links.new(stains.outputs['Fac'], weathering.inputs[0])
        wear = nodes.new('ShaderNodeMixRGB')
        wear.blend_type = 'MULTIPLY'
        wear.inputs[0].default_value = 0.62
        links.new(ramp.outputs[0], wear.inputs[1])
        links.new(weathering.outputs[0], wear.inputs[2])
        links.new(wear.outputs[0], shader.inputs['Base Color'])
    return mat


leather = material('Oiled walnut leather', (0.016, 0.013, 0.018), 0.43, grain=95)
lining = material('Dark suede endpaper', (0.067, 0.045, 0.023), 0.88, grain=145)
paper = material('Smoked parchment', (0.135, 0.095, 0.051), 0.94, grain=210)
edge = material('Uncut paper edges', (0.32, 0.235, 0.12), 0.9, grain=170)
brass = material('Antique brass', (0.36, 0.235, 0.085), 0.33, 0.78, grain=75)
dark = material('Binding creases', (0.012, 0.007, 0.003), 0.88)
thread = material('Flax sewing thread', (0.38, 0.29, 0.15), 0.92)


def box(name, location, dimensions, mat, bevel=0, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new('Worn rounded edges', 'BEVEL')
        mod.width, mod.segments = bevel, 3
        obj.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
    if parent:
        obj.parent = parent
    return obj


def line(name, points, radius, mat, parent=None, cyclic=False):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for p, co in zip(spline.points, points):
        p.co = (*co, 1)
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj.parent = parent
    return obj


def cover_material():
    mat = bpy.data.materials.new('Gilded runic leather relief')
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.get('Principled BSDF')
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = bpy.data.images.load(str(Path(__file__).resolve().parent.parent / 'assets/book-source/foil' / f'{args.variant}.png'))
    texture.image.pack()
    links.new(texture.outputs['Color'], shader.inputs['Base Color'])
    shader.inputs['Roughness'].default_value = 0.46
    shader.inputs['Specular IOR Level'].default_value = 0.3
    relief = nodes.new('ShaderNodeRGBToBW')
    links.new(texture.outputs['Color'], relief.inputs[0])
    bump = nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.07
    bump.inputs['Distance'].default_value = 0.012
    links.new(relief.outputs[0], bump.inputs['Height'])
    links.new(bump.outputs[0], shader.inputs['Normal'])
    foil = nodes.new('ShaderNodeMapRange')
    foil.inputs['From Min'].default_value = 0.035
    foil.inputs['From Max'].default_value = 0.35
    foil.inputs['To Min'].default_value = 0.05
    foil.inputs['To Max'].default_value = 0.75
    links.new(relief.outputs[0], foil.inputs['Value'])
    links.new(foil.outputs[0], shader.inputs['Metallic'])
    return mat


ornament = cover_material()


W, H = 8, 5.4
box('Back leather board', (W/2, 0, -0.39), (W+0.20, H+0.24, 0.20), leather, 0.075)
for i in range(24):
    z = -0.25 + i * 0.021
    box('Deckled page %02d' % i, (W/2 + 0.015 * math.sin(i*2.3), 0, z),
        (W-0.06, H-0.05+0.012*math.sin(i*1.7), 0.012), edge, 0.008)

# The widget area is planar; curvature lives outside its registration rectangle.
verts, faces = [], []
for row in range(2):
    for i in range(97):
        x = W * i/96
        z = 0.29 - 0.19*math.exp(-x/0.19) + 0.11*math.exp(-((x-0.46)/0.30)**2) - 0.08*math.exp(-(W-x)/0.14)
        verts.append((x, (-1 if row == 0 else 1)*H/2, z))
for i in range(96):
    faces.append((i, i+1, 98+i, 97+i))
mesh = bpy.data.meshes.new('Curved folio')
mesh.from_pydata(verts, [], faces)
mesh.update()
obj = bpy.data.objects.new('Open parchment', mesh)
scene.collection.objects.link(obj)
obj.data.materials.append(paper)
for poly in mesh.polygons:
    poly.use_smooth = True
line('Gutter stitching', [(0.12, -H/2+0.1, 0.26), (0.12, H/2-0.1, 0.26)], 0.018, dark)
for y in [-1.95, -0.65, 0.65, 1.95]:
    line('Sewn signature', [(0.04,y-0.10,0.27),(0.11,y,0.29),(0.04,y+0.10,0.27)], 0.012, thread)

bpy.ops.object.empty_add()
cover = bpy.context.object
cover.name = 'Cover hinge'
cover.location = (0,0,0.39)
box('Thick front leather board', (W/2,0,0), (W+0.20,H+0.24,0.18), leather,0.065,cover)
box('Inset suede lining', (W/2,0,-0.105), (W-0.35,H-0.28,0.035),lining,0.035,cover)
for face in [-1,1]:
    z = face * 0.125
    mesh = bpy.data.meshes.new('Illuminated cover panel')
    corners = [(0,-H/2,z),(W,-H/2,z),(W,H/2,z),(0,H/2,z)]
    mesh.from_pydata(corners, [], [(0,1,2,3) if face > 0 else (3,2,1,0)])
    mesh.uv_layers.new()
    coords = [(0,0),(1,0),(1,1),(0,1)]
    for loop in mesh.loops:
        mesh.uv_layers.active.data[loop.index].uv = coords[loop.vertex_index]
    obj = bpy.data.objects.new('Runic cover relief', mesh)
    scene.collection.objects.link(obj)
    obj.parent = cover
    obj.data.materials.append(ornament)
    for inset in [0.03,0.09]:
        line('Raised gilt rim', [(inset,-H/2+inset,z),(W-inset,-H/2+inset,z),
            (W-inset,H/2-inset,z),(inset,H/2-inset,z)], .008, brass, cover, True)
for y in [-1.95,-0.65,0.65,1.95]:
    box('Raised binding rib',(0.035,y,0),(0.25,0.12,0.27),leather,0.045,cover)

leaves = []
for index in range(2):
    bpy.ops.object.empty_add(location=(0,0,0.32+index*0.02))
    hinge = bpy.context.object
    hinge.name = 'Turning flyleaf hinge'
    vertices, quads = [], []
    for row in range(2):
        for i in range(49):
            u=i/48
            vertices.append(((W-0.12)*u, (-1 if row == 0 else 1)*(H/2-0.07), 0.09*math.sin(u*math.pi)))
    for i in range(48):
        quads.append((i,i+1,i+50,i+49))
    mesh=bpy.data.meshes.new('Flexible flyleaf')
    mesh.from_pydata(vertices,[],quads)
    mesh.update()
    obj=bpy.data.objects.new('Bound flyleaf',mesh)
    scene.collection.objects.link(obj)
    obj.parent=hinge
    obj.data.materials.append(paper)
    thickness=obj.modifiers.new('Paper thickness','SOLIDIFY')
    thickness.thickness=0.009
    for polygon in mesh.polygons:
        polygon.use_smooth=True
    leaves.append(hinge)

bpy.ops.object.camera_add(location=(2.95,-3,50))
camera=bpy.context.object
camera.name='Page registration camera'
camera.data.type='PERSP'
camera.data.lens=144
camera.data.sensor_width=36
camera.rotation_euler=(Vector((2.95,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
scene.camera=camera

def light(name,location,power,size,color):
    bpy.ops.object.light_add(type='AREA', location=location)
    obj=bpy.context.object
    obj.name=name
    obj.data.energy=power
    obj.data.shape='DISK'
    obj.data.size=size
    obj.data.color=color
    obj.rotation_euler=(Vector((3,0,0))-obj.location).to_track_quat('-Z','Y').to_euler()

light('Warm window',(-3,5,11),1250,7,(1,0.85,0.65))
light('Soft page fill',(7,-2,9),650,8,(0.78,0.86,1))
light('Spine rim',(-4,-3,6),700,4,(1,0.7,0.4))
scene.frame_end=args.frames
for frame in range(1,args.frames+1):
    p=(frame-1)/(args.frames-1)
    cover.rotation_euler[1]=-math.radians(p*100)
    cover.keyframe_insert(data_path='rotation_euler', frame=frame)
    for index, leaf in enumerate(leaves):
        turn=max(0,min(1,(p-0.045-index*0.03)/(0.955-index*0.03)))
        leaf.rotation_euler[1]=-math.radians(turn*(94+index))
        leaf.keyframe_insert(data_path='rotation_euler',frame=frame)
scene.frame_set(args.frames)
bpy.context.view_layer.update()
points=[world_to_camera_view(scene,camera,Vector((x,y,0.29))) for x,y in [(0,H/2),(W,-H/2),(W,H/2),(0,-H/2)]]
registration={'left':min(p.x for p in points),'top':1-max(p.y for p in points),'width':max(p.x for p in points)-min(p.x for p in points),'height':max(p.y for p in points)-min(p.y for p in points),'frames':args.frames}
poses=[]
for frame in range(1,args.frames+1):
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    pose={}
    for name,point in [('hingeTop',(0,H/2,0)),('hingeBottom',(0,-H/2,0)),('edgeTop',(W,H/2,0)),('edgeBottom',(W,-H/2,0))]:
        world=cover.matrix_world @ Vector(point)
        projected=world_to_camera_view(scene,camera,world)
        pose[name]=[projected.x,1-projected.y,world.z]
    poses.append(pose)
registration['poses']=poses
(args.output/'registration.json').write_text(json.dumps(registration,indent=2)+'\n')
args.blend.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(args.blend.resolve()))
frames=[] if args.no_render else [args.frames] if args.preview else range(1,args.frames+1)
for frame in frames:
    scene.frame_set(frame)
    scene.render.filepath=str((args.output/f'book-{frame:02}.png').resolve())
    bpy.ops.render.render(write_still=True)
