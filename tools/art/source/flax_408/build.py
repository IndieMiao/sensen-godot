"""SGODOT-408: low flax patch, readable blue five-petal flowers; Blender 5.2.

Run from any directory with blender --background --factory-startup --python <this>.
Coordinates below are metres, Godot Y up. Named source parts stay editable.
"""
from pathlib import Path
import hashlib
import json
import math
import random
import bpy
import bmesh
from mathutils import Vector

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[3]
KIT = ROOT / 'assets/farm/art'
COLORS = {'stem': '799973', 'leaf': '90AC7F', 'leaf_light': 'A1B88B',
          'blue': '85ACE6', 'blue_light': 'A0C3EE', 'blue_shade': '6E98D7',
          'pollen': 'E6D6A1', 'soil': 'B4946D', 'soil_edge': 'C3A57D', 'soil_dark': '9E805F'}
PARTS = []
MATS = {}
RNG = random.Random(408)

def linear(h):
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4
                 for v in [c / 255 for c in bytes.fromhex(h)])

def vector(p):
    return Vector((p[0], -p[2], p[1]))

def material(role):
    if role not in MATS:
        m = bpy.data.materials.new(role)
        m.diffuse_color = (*linear(COLORS[role]), 1)
        m.use_nodes = True
        bsdf = m.node_tree.nodes['Principled BSDF']
        bsdf.inputs['Base Color'].default_value = m.diffuse_color
        bsdf.inputs['Roughness'].default_value = .9
        bsdf.inputs['Specular IOR Level'].default_value = .16
        MATS[role] = m
    return MATS[role]

def mesh(name, points, faces, roles, smooth=False, closed=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata([vector(p) for p in points], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = pivot
    if isinstance(roles, str): roles = [roles] * len(faces)
    names = list(dict.fromkeys(roles))
    for key in names: data.materials.append(material(key))
    for face, role in zip(data.polygons, roles):
        face.material_index = names.index(role)
        face.use_smooth = smooth
    if closed:
        bm = bmesh.new(); bm.from_mesh(data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(data); bm.free()
    PARTS.append(obj)
    return obj

def stem(name, base, tip):
    a, b = Vector(base), Vector(tip)
    axis = (b-a).normalized()
    side = axis.cross(Vector((1, 0, 0))).normalized()
    other = axis.cross(side).normalized()
    points = [tuple(p+r*(math.cos(i*math.tau/4)*side+math.sin(i*math.tau/4)*other))
              for p, r in [(a, .010), (b, .007)] for i in range(4)]
    faces = [(i, (i+1)%4, (i+1)%4+4, i+4) for i in range(4)]
    faces += [(3, 2, 1, 0), (4, 5, 6, 7)]
    mesh(name, points, faces, 'stem', True, True)

def leaf(name, at, angle, length, role):
    a = Vector(at)
    direction = Vector((math.cos(angle), .65, math.sin(angle))).normalized()
    side = Vector((-math.sin(angle), 0, math.cos(angle)))
    pts = [a, a+direction*length*.52+side*.026,
           a+direction*length, a+direction*length*.52-side*.026]
    # Explicit backs: the runtime FarmArt material uses normal backface culling.
    mesh(name, pts+pts, [(0, 2, 1), (0, 3, 2), (5, 6, 4), (6, 7, 4)], role)

def flower(name, at, radius, tilt, spin):
    # Shallow, slightly cupped five-lobed bloom with a tiny cream centre.
    # Top: 25 triangles; underside: 15, sharing the rim; one opaque material.
    center = Vector(at)
    u = Vector((math.cos(spin), 0, math.sin(spin)))
    normal = Vector((.10*math.sin(spin), 1, tilt)).normalized()
    u = (u-normal*u.dot(normal)).normalized()
    w = normal.cross(u)
    def p(r, angle, height):
        return center+u*(r*math.cos(angle))+w*(r*math.sin(angle))+normal*height
    pts = [center]
    for i in range(5): pts.append(p(radius*.20, i*math.tau/5-math.pi/5, .002))
    for i in range(5):
        for angle, r in [(-36, .53), (-14, 1), (14, 1)]:
            pts.append(p(radius*r, i*math.tau/5+math.radians(angle), .012 if r==1 else .004))
    pts.append(center-normal*.008)
    faces = []; roles = []
    for i in range(5):
        a, b = 1+i, 1+(i+1)%5
        c, d, e, f = 6+3*i, 6+3*i+1, 6+3*i+2, 6+3*((i+1)%5)
        faces += [(0,a,b),(a,c,d),(a,d,e),(a,e,b),(b,e,f)]
        roles += ['pollen','blue','blue_light' if i%2==0 else 'blue','blue','blue_shade']
    for i in range(15): faces.append((21,6+(i+1)%15,6+i)); roles.append('blue_shade')
    # u cross w = normal, so all top faces above are outward.
    mesh(name, pts, faces, roles, False)

bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
pivot = bpy.data.objects.new('Flax / ground-centre origin', None)
bpy.context.scene.collection.objects.link(pivot)
pivot['author'] = '黄忠'; pivot['task'] = 'SGODOT-408'
points = []
for level, factor in [(0, .94), (.017, 1), (.046, .88)]:
    for i in range(16):
        a = i*math.tau/16
        wobble = 1 if i%4==0 else [1,.975,.99,.97][i%4]
        points.append((.65*math.cos(a)*factor*wobble, level, .63*math.sin(a)*factor*wobble))
points.append((0, .047, 0))
faces = [tuple(reversed(range(16)))]; roles = ['soil_dark']
for ring in range(2):
    for i in range(16):
        j = (i+1)%16
        faces.append((ring*16+i,ring*16+j,(ring+1)*16+j,(ring+1)*16+i))
        roles.append('soil_dark' if ring==0 else 'soil_edge')
for i in range(16): faces.append((48,32+i,32+(i+1)%16)); roles.append('soil')
mesh('Soft light-brown soil border', points, faces, roles, True, True)

flowers = []
for i in range(12):
    outer = i < 8
    angle = (i if outer else i-8+.3)*math.tau/(8 if outer else 4)
    reach = (.46 if outer else .20) * RNG.uniform(.94, 1.03)
    y = RNG.uniform(.52, .60) if outer else [.61,.63,.650,.615][i-8]
    tip = Vector((math.cos(angle)*reach, y, math.sin(angle)*reach))
    base = Vector((tip.x*.83, .042, tip.z*.83))
    stem(f'Stem {i+1:02}', base, tip)
    for j, t in enumerate([.36,.66]):
        leaf(f'Stem {i+1:02} / lanceolate leaf {j+1}',base.lerp(tip,t),angle+j*2.7,.15 if j==0 else .12,
             'leaf' if j==0 else 'leaf_light')
    radius = RNG.uniform(.092, .105)
    flower(f'Blue five-petal bloom {i+1:02}', tip, radius, .12+RNG.random()*.20, angle+.2)
    flowers.append({'center':list(tip),'diameter_m':radius*2})
for i in range(4):
    angle = (i+.5)*math.tau/4
    base = Vector((.31*math.cos(angle), .042, .31*math.sin(angle)))
    tip = base+Vector((.05*math.cos(angle),.37,.05*math.sin(angle)))
    stem(f'Young stem {i+1}',base,tip)
    for j in range(2): leaf(f'Young stem {i+1} / leaf {j+1}',base.lerp(tip,.45+j*.3),angle+j*2.8,.14,'leaf')

bpy.context.view_layer.update()
stats = {}
for obj in PARTS:
    obj.data.calc_loop_triangles(); stats[obj.name] = len(obj.data.loop_triangles)
scene = bpy.context.scene
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'flax_patch.blend'))
export = bpy.data.scenes.new('Temporary mobile export')
flat = bpy.data.materials.new('Farm vertex paint'); flat.use_nodes = True
bsdf = flat.node_tree.nodes['Principled BSDF']
bsdf.inputs['Base Color'].default_value = (1,1,1,1)
bsdf.inputs['Roughness'].default_value = .9
bsdf.inputs['Metallic'].default_value = 0
bsdf.inputs['Specular IOR Level'].default_value = .16
node = flat.node_tree.nodes.new('ShaderNodeVertexColor'); node.layer_name = 'Color'
flat.node_tree.links.new(node.outputs['Color'],bsdf.inputs['Base Color'])
copies = []
for obj in PARTS:
    data = obj.data.copy(); data.transform(obj.matrix_world)
    layer = data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
    for face in data.polygons:
        color = data.materials[face.material_index].diffuse_color
        for loop in face.loop_indices: layer.data[loop].color = color
    data.materials.clear(); data.materials.append(flat)
    for face in data.polygons: face.material_index = 0
    data.color_attributes.active_color = layer; data.color_attributes.render_color_index = 0
    copy = bpy.data.objects.new('Export part',data); export.collection.objects.link(copy); copies.append(copy)
bpy.context.window.scene = export
for obj in copies: obj.select_set(True)
bpy.context.view_layer.objects.active = copies[0]; bpy.ops.object.join()
body = bpy.context.object; body.name = 'flax_patch'; body.data.name = 'flax_patch_mobile'
bm = bmesh.new(); bm.from_mesh(body.data); bmesh.ops.triangulate(bm,faces=list(bm.faces)); bm.to_mesh(body.data); bm.free()
body.data.calc_loop_triangles(); triangles = len(body.data.loop_triangles)
assert triangles <= 900, triangles
path = KIT/'flax_patch.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,
    export_yup=True,export_materials='EXPORT',export_vertex_color='ACTIVE',export_all_vertex_colors=False,
    export_normals=True,export_texcoords=False,export_animations=False,export_cameras=False,export_lights=False)
coords = [Vector((v.co.x,v.co.z,-v.co.y)) for v in body.data.vertices]
lo = [min(v[i] for v in coords) for i in range(3)]; hi = [max(v[i] for v in coords) for i in range(3)]
meta = {'generator':'tools/art/source/flax_408/build.py','source':'tools/art/source/flax_408/flax_patch.blend',
    'task':'SGODOT-408','revision':'v1','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
    'triangles':triangles,'triangle_limit':900,'surfaces':1,'bytes':path.stat().st_size,
    'bounds':[lo,hi],'bounds_blender':[[lo[0],-hi[2],lo[1]],[hi[0],-lo[2],hi[1]]],
    'dimensions_xyz':[hi[i]-lo[i] for i in range(3)],'origin':'bottom / footprint centre; Y up, +Z front; metres',
    'mesh':'flax_patch_mobile','material':'Farm vertex paint / FarmArt.material(); linear vertex colour, matte, no textures',
    'palette_srgb':COLORS,'flowers':flowers,'source_parts_triangles':stats,
    'animations':[],'skeleton':False,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
manifest = KIT/'manifest.json'; content = json.loads(manifest.read_text()); content['assets']['flax_patch'] = meta
manifest.write_text(json.dumps(content,ensure_ascii=False,indent=2)+'\n')
bpy.context.window.scene = scene; bpy.data.scenes.remove(export)
print('FLAX_READY',triangles,lo,hi,flush=True)
