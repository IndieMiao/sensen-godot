#!/usr/bin/env python3
"""Build SGODOT-324 from measured, named source meshes. Run inside Blender.

Temporary Basic Room swatches; no source-room atlas or room-contact AO is copied.
All dimensions are metres. Blender Z-up maps to exported Godot Y-up/front +Z.
"""
import ast
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys

import bpy
from mathutils import Matrix, Vector
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/rooms/_shared/shell_hall'
SOURCE = ROOT / 'tools/art/source/hallkit_324'
sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_chef_sign import load_glb, accessor

H = 1.745
SEAT = .715
SLOTS = ['oak', 'oak_light', 'oak_edge', 'brass', 'linen', 'sky', 'sage', 'iron',
         'porcelain', 'sage_dark', 'linen_green', 'petal',
         'print_portrait', 'print_landscape', 'glass', 'stone']
KITS = {}
SOURCES = {}
MATERIALS = {}


def dump(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def glb_stats(path):
    doc, blob = load_glb(path)
    points, triangles, surfaces = [], 0, 0
    # These room exports contain already-applied transforms, checked below.
    for node in doc['nodes']:
        if 'mesh' in node:
            assert all(abs(v) < 1e-5 for v in node.get('translation', [0, 0, 0]))
            assert np.allclose(node.get('scale', [1, 1, 1]), [1, 1, 1])
            assert np.allclose(node.get('rotation', [0, 0, 0, 1]), [0, 0, 0, 1])
            assert np.allclose(node.get('matrix', np.eye(4).flatten()), np.eye(4).flatten())
    for mesh in doc['meshes']:
        for prim in mesh['primitives']:
            points.extend(accessor(doc, blob, prim['attributes']['POSITION']))
            triangles += len(accessor(doc, blob, prim['indices'])) // 3
            surfaces += 1
    points = np.array(points)
    lo, hi = points.min(0), points.max(0)
    return {'triangles': triangles, 'surfaces': surfaces, 'bounds': [lo.tolist(), hi.tolist()],
            'dimensions_xyz_m': (hi-lo).tolist(), 'sha256': digest(path)}


def bounds(objects):
    pts = [v.co[:] for obj in objects for v in obj.data.vertices]
    a = np.array(pts)
    return a.min(0), a.max(0)


def transform(objects, scale=(1, 1, 1), offset=(0, 0, 0)):
    matrix = Matrix.Translation(Vector(offset)) @ Matrix.Diagonal((*scale, 1))
    for obj in objects:
        obj.data.transform(matrix)
        obj.data.update()


def import_parts(kit, source_kit, source_asset):
    blend = ROOT / 'tools/art/source' / source_kit / (source_kit + '.blend')
    glb = ROOT / 'assets/rooms' / source_kit / (source_asset + '.glb')
    key = source_kit + '/' + source_asset
    if key not in SOURCES:
        SOURCES[key] = {'glb': str(glb.relative_to(ROOT)), **glb_stats(glb),
                        'blend': str(blend.relative_to(ROOT)), 'blend_sha256': digest(blend),
                        'collection': 'KIT_' + source_asset}
    with bpy.data.libraries.load(str(blend), link=False) as (src, dst):
        dst.collections = ['KIT_' + source_asset]
    collection = dst.collections[0]
    assert collection is not None, key
    bpy.context.scene.collection.children.link(collection)
    for obj in collection.objects:
        if obj.type == 'EMPTY':
            obj.location = (0, 0, 0)
            obj.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    parts = []
    for obj in list(collection.objects):
        if obj.type != 'MESH':
            continue
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(deps), depsgraph=deps)
        mesh.transform(obj.matrix_world)
        part = bpy.data.objects.new(obj.name, mesh)
        KITS[kit]['collection'].objects.link(part)
        part['source_part'] = obj.name
        part['source_asset'] = key
        part['source_materials'] = json.dumps([m.name for m in mesh.materials])
        part['export_group'] = 'Body'
        parts.append(part)
    for obj in list(collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(collection)
    lo, hi = bounds(parts)
    source = SOURCES[key]
    actual = np.array([hi[0]-lo[0], hi[2]-lo[2], hi[1]-lo[1]])
    assert np.allclose(actual, source['dimensions_xyz_m'], atol=2e-6), key
    count = 0
    for part in parts:
        part.data.calc_loop_triangles()
        count += len(part.data.loop_triangles)
    assert count == source['triangles'], (key, count)
    KITS[kit]['sources'].append(key)
    return parts


def begin(name, family, modules, notes):
    collection = bpy.data.collections.new('KIT_' + name)
    bpy.context.scene.collection.children.link(collection)
    KITS[name] = {'name': name, 'family': family, 'modules': modules, 'changes': notes,
                  'collection': collection, 'sources': [], 'anchors': {}}


def parts(name):
    return list(KITS[name]['collection'].objects)


def remove(objects):
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)


def recolour(obj, slot):
    obj['palette_slot'] = slot


def default_slot(obj):
    names = json.loads(obj.get('source_materials', '[]'))
    for slot in sorted(SLOTS, key=len, reverse=True):
        if any(n.startswith(slot + '_') for n in names):
            return slot
    return 'linen'


def resize_y_to(objects, top, floor=None):
    lo, hi = bounds(objects)
    floor = lo[2] if floor is None else floor
    factor = top / (hi[2]-floor)
    transform(objects, (1, 1, factor), (0, 0, -floor*factor))
    return float(factor)


def make_furniture():
    for name, armchair, modules in [('sofa_three_seat', False, ['N1 M13', 'N1 M14', 'N2 M15']),
                                     ('armchair', True, ['N1 M12', 'N2 M16'])]:
        begin(name, 'armchair' if armchair else 'sofa', modules,
              ['Named Deluxe geometry copied; seat top corrected to 0.715 m.',
               'Single seat, shortened base/back; original arm thickness retained.' if armchair
               else 'Two source seat cushions replaced by three copies of the same cushion geometry.',
               'Temporary Basic Room linen/sky upholstery; source atlas and checked fabric discarded.'])
        objects = import_parts(name, 'deluxe_room_10', 'sofa')
        seats = [o for o in objects if o['source_part'].startswith('Plump seat cushion')]
        pillows = [o for o in objects if o['source_part'].startswith('Puffed loose cushion')]
        seat_top = bounds(seats)[1][2]
        if armchair:
            shortening = (SOURCES['deluxe_room_10/sofa']['dimensions_xyz_m'][0] - 1.50)/2
            for obj in objects:
                if obj in seats or obj in pillows:
                    continue
                lo, hi = bounds([obj]); center = (lo+hi)/2
                if 'base' in obj['source_part'] or 'back' in obj['source_part']:
                    transform([obj], ((hi[0]-lo[0]-2*shortening)/(hi[0]-lo[0]), 1, 1))
                else:
                    transform([obj], offset=(-math.copysign(shortening, center[0]), 0, 0))
            remove(seats[1:]); seats = seats[:1]
            lo, hi = bounds(seats)
            transform(seats, offset=(-(lo[0]+hi[0])/2, 0, 0))
            transform(seats, (.99/(hi[0]-lo[0]), 1, 1))
            remove(pillows[1:]); pillows = pillows[:1]
            lo, hi = bounds(pillows)
            transform(pillows, offset=(-(lo[0]+hi[0])/2, 0, 0))
            transform(pillows, (.55/(hi[0]-lo[0]), 1, 1))
            xs = [0]
        else:
            template = seats[0]
            mesh = template.data.copy()
            lo, hi = bounds([template])
            mesh.transform(Matrix.Translation(Vector((-(lo[0]+hi[0])/2, 0, 0))))
            mesh.transform(Matrix.Diagonal((.758/(hi[0]-lo[0]), 1, 1, 1)))
            for i, x in enumerate([-.766, 0, .766]):
                obj = template.copy(); obj.data = mesh.copy(); obj.name = 'Seat cushion ' + str(i+1)
                KITS[name]['collection'].objects.link(obj)
                transform([obj], offset=(x, 0, 0))
            remove(seats)
            xs = [-.675, 0, .675]
        factor = SEAT / seat_top
        transform(parts(name), (1, 1, factor))
        KITS[name]['seat_height_m'] = SEAT
        KITS[name]['vertical_scale'] = factor
        for i, x in enumerate(xs):
            KITS[name]['anchors']['seat_' + str(i+1)] = [x, SEAT, .22]
        for obj in parts(name):
            label = obj['source_part']
            if any(t in label for t in ['upholstered', 'seat cushion']):
                recolour(obj, 'linen' if armchair else 'sky')
            elif 'loose cushion' in label:
                recolour(obj, 'sage' if armchair else 'linen')

    begin('bench_three_seat', 'bench', ['N3 M15'],
          ['Black leather changed to provisional sage; steel to Basic Room iron.',
           'Width/depth retained; actual cushion surface lifted to 0.715 m.'])
    objects = import_parts('bench_three_seat', 'clothing_store_a', 'black_tufted_bench')
    seat_top = bounds([o for o in objects if 'continuous cushion' in o['source_part']])[1][2]
    transform(objects, (1, 1, SEAT/seat_top))
    KITS['bench_three_seat']['seat_height_m'] = SEAT
    KITS['bench_three_seat']['vertical_scale'] = SEAT/seat_top
    for i, x in enumerate([-.72, 0, .72]):
        KITS['bench_three_seat']['anchors']['seat_' + str(i+1)] = [x, SEAT, 0]
    for obj in objects:
        label = obj['source_part'].lower()
        if 'seam' in label:
            transform([obj], offset=(0, 0, SEAT-.0002-bounds([obj])[1][2]))
        elif 'stitch' in label:
            transform([obj], offset=(0, 0, SEAT+.0004-bounds([obj])[1][2]))
        recolour(obj, 'linen' if 'stitch' in label else 'sage_dark' if 'seam' in label
                 else 'sage' if 'cushion' in label else 'iron')

    begin('round_side_table', 'table', ['N1 M16', 'N2 M17'],
          ['Coffee Shop 0 selected from three measured candidates: smallest diameter (1.10 m), 240 triangles.',
           'Grounded at actual lowest vertex; tabletop 0.65H = 1.13425 m; diameter retained.'])
    objects = import_parts('round_side_table', 'coffee_shop_0', 'round_table')
    KITS['round_side_table']['vertical_scale'] = resize_y_to(objects, .65*H)
    KITS['round_side_table']['tabletop_height_m'] = .65*H

    begin('round_stool', 'stool', ['N3 M16'],
          ['Mine Hut stool geometry retained; source negative foot bound grounded.',
           'Seat top corrected to 0.715 m; original horizontal dimensions retained.'])
    objects = import_parts('round_stool', 'mine_hut', 'round_stool')
    KITS['round_stool']['vertical_scale'] = resize_y_to(objects, SEAT)
    KITS['round_stool']['seat_height_m'] = SEAT
    KITS['round_stool']['anchors']['seat_1'] = [0, SEAT, 0]

    begin('wall_sconce', 'sconce', ['N2 M23', 'N3 M08'],
          ['Original 292-triangle lamp retained; mounting back moved to Z=0.',
           'Basic Room brass / petal swatches; suggested local light belongs to room assembly.'])
    objects = import_parts('wall_sconce', 'clothing_store_b', 'wall_sconce')
    transform(objects, offset=(0, -bounds(objects)[1][1], 0))
    for obj in objects:
        recolour(obj, 'petal' if 'Opal' in obj['source_part'] else 'brass')
    KITS['wall_sconce']['anchors']['light'] = [0, 0, .22]


def plane(name, vertices, faces, collection, slot, group):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces); mesh.update()
    obj = bpy.data.objects.new(name, mesh); collection.objects.link(obj)
    obj['palette_slot'] = slot; obj['export_group'] = group
    obj['source_part'] = 'New ' + name
    return obj


def make_frames():
    for name, source, original, slot, modules in [
        ('frame_portrait', 'standard_room_5', 'botanical_picture', 'print_portrait', ['N1 M22', 'N3 M06']),
        ('frame_landscape', 'tavern', 'landscape_frame', 'print_landscape', ['N1 M23', 'N3 M07'])]:
        begin(name, 'frames', modules, ['Named backing and four frame rails retained at original dimensions.',
              'Old botanical / landscape relief removed; independent two-triangle Artwork node with its own atlas rectangle.',
              'Mounting back at Z=0; placeholder abstract print, pending N1/N3 artwork.'])
        objects = import_parts(name, source, original)
        remove([o for o in objects if not o['source_part'].startswith('Picture')])
        objects = parts(name)
        backing = next(o for o in objects if o['source_part'].startswith('Picture backing'))
        lo, hi = bounds([backing]); w, h = hi[0]-lo[0]-.054, hi[2]-lo[2]-.054
        plane('Artwork', [(-w/2, -.025, -h/2), (w/2, -.025, -h/2),
                          (w/2, -.025, h/2), (-w/2, -.025, h/2)],
              [(0, 1, 2, 3)], KITS[name]['collection'], slot, 'Artwork')
        transform(parts(name), offset=(0, -bounds(parts(name))[1][1], 0))
        KITS[name]['artwork'] = {'node': 'Artwork', 'size_m': [float(w), float(h)],
                                 'palette_slot': slot, 'replacement': 'Replace this mesh or remap only its UV rectangle; Body unchanged.'}


def make_displays():
    for name, source, original, modules in [
        ('display_cabinet', 'bakery', 'pastry_display', ['N3 M10']),
        ('display_island', 'clothing_store_b', 'round_display_island', ['N3 M13'])]:
        begin(name, 'display', modules, ['Original named cabinet / island base retained, top at 0.66H = 1.1517 m.',
              'Bakery curved glass profile reused, resized to 0.60 m canopy height.',
              'Added closed side/rear panes and thin brass canopy edging; Glass is the only transparent surface. No merchandise.'])
        objects = import_parts(name, source, original)
        KITS[name]['vertical_scale'] = resize_y_to(objects, .66*H)
        KITS[name]['tabletop_height_m'] = .66*H
        glass = import_parts(name, 'bakery', 'display_glass')
        lo, hi = bounds(glass)
        horizontal = .5 if name == 'display_island' else 1.0
        transform(glass, (horizontal, horizontal, .6/(hi[2]-lo[2])),
                  (0, 0, .66*H-lo[2]*.6/(hi[2]-lo[2])))
        for obj in glass:
            obj['export_group'] = 'Glass'; recolour(obj, 'glass')
        # Source is an open curved sheet. End/back planes close it against the top.
        profile = sorted({(round(v.co.y, 7), round(v.co.z, 7)) for v in glass[0].data.vertices})
        low = .66*H
        profile.append((max(y for y, z in profile), low))
        x = (hi[0]-lo[0])/2*horizontal
        for side in [-1, 1]:
            vertices = [(side*x, y, z) for y, z in profile]
            winding = tuple(range(len(vertices)))
            if side < 0: winding = tuple(reversed(winding))
            plane('Glass side pane', vertices, [winding], KITS[name]['collection'], 'glass', 'Glass')
        back_y = max(y for y, z in profile); top = max(z for y, z in profile)
        plane('Glass rear pane', [(-x, back_y, low), (-x, back_y, top),
                                  (x, back_y, top), (x, back_y, low)],
              [(0, 1, 2, 3)], KITS[name]['collection'], 'glass', 'Glass')
        for side in [-1, 1]:
            points = [Vector((side*x, y, z)) for y, z in profile]
            for a, b in zip(points, points[1:]+points[:1]):
                rail(name, a, b)
        for y, z in [profile[0], profile[-2], profile[-1]]:
            rail(name, Vector((-x, y, z)), Vector((x, y, z)))


def rail(name, a, b):
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=.009, depth=(b-a).length,
                                      location=(a+b)/2)
    obj = bpy.context.object
    obj.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    bpy.context.view_layer.update()
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    for collection in list(obj.users_collection): collection.objects.unlink(obj)
    KITS[name]['collection'].objects.link(obj)
    obj.name = 'Canopy brass edge'
    obj['source_part'] = 'New 9 mm radius canopy brass edge'
    obj['export_group'] = 'Body'
    recolour(obj, 'brass')


def swatch_rect(slot):
    i = SLOTS.index(slot); col, row = i % 4, i // 4
    # glTF UV origin is upper-left; 32px padding at 2048 keeps minified edges clean.
    return [(col*512+32)/2048, 1-((row+1)*512-32)/2048,
            ((col+1)*512-32)/2048, 1-(row*512+32)/2048]


def atlas():
    tree = ast.parse((ROOT/'tools/art/build_basic_room.py').read_text())
    palette = next(ast.literal_eval(n.value) for n in tree.body
                   if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'PALETTE' for t in n.targets))
    palette.update({'print_portrait': palette['linen'], 'print_landscape': palette['linen'], 'glass': palette['sky']})
    pixels = np.ones((2048, 2048, 4), dtype=np.float32)
    for i, slot in enumerate(SLOTS):
        colour = np.array([int(palette[slot][j:j+2], 16)/255 for j in [0, 2, 4]])
        y, x = i//4*512, i%4*512
        pixels[y:y+512, x:x+512, :3] = colour
    def rect(slot, box, colour):
        i = SLOTS.index(slot); y, x = i//4*512, i%4*512
        x0, y0, x1, y1 = box
        pixels[y+y0:y+y1, x+x0:x+x1, :3] = [int(palette[colour][j:j+2], 16)/255 for j in [0, 2, 4]]
    rect('print_portrait', (110, 100, 240, 350), 'sage')
    rect('print_portrait', (240, 210, 380, 410), 'sky')
    rect('print_portrait', (160, 370, 320, 405), 'oak')
    rect('print_landscape', (90, 250, 420, 420), 'sky')
    rect('print_landscape', (90, 95, 250, 250), 'sage')
    rect('print_landscape', (270, 110, 410, 200), 'oak_light')
    image = bpy.data.images.new('Hallkit Basic Room provisional palette', 2048, 2048, alpha=False)
    image.pixels.foreach_set(pixels.ravel()); image.filepath_raw = str(OUT/'hallkit_palette.png')
    image.file_format = 'PNG'; image.save()
    image.pack()
    data = {'status': 'provisional_until_SGODOT_319', 'source': 'tools/art/build_basic_room.py:PALETTE',
            'source_sha256': digest(ROOT/'tools/art/build_basic_room.py'), 'size': [2048, 2048],
            'ao': 'None in temporary swatches. Room-contact AO must be baked after placement in N1/N2.',
            'slots': {s: {'hex_srgb': palette[s], 'uv_rect_gltf': swatch_rect(s)} for s in SLOTS}}
    dump(OUT/'palette.json', data)
    for name, alpha in [('HallOpaque', 1), ('HallGlass', .14)]:
        mat = bpy.data.materials.new(name); mat.use_nodes = True
        shader = mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Roughness'].default_value = .78 if alpha == 1 else .16
        shader.inputs['Alpha'].default_value = alpha
        node = mat.node_tree.nodes.new('ShaderNodeTexImage'); node.image = image
        mat.node_tree.links.new(node.outputs['Color'], shader.inputs['Base Color'])
        MATERIALS[name] = mat


def map_uv(obj):
    slot = obj.get('palette_slot', default_slot(obj)); obj['palette_slot'] = slot
    # Non-render UVs are intentionally kept in the editable source only.
    layer = obj.data.uv_layers.new(name='HallPalette')
    obj.data.uv_layers.active_index = len(obj.data.uv_layers)-1
    layer.active_render = True
    rect = swatch_rect(slot); u0, v0, u1, v1 = rect
    lo, hi = bounds([obj]); extent = np.maximum(hi-lo, 1e-8)
    for face in obj.data.polygons:
        axis = int(np.argmax(np.abs(face.normal[:])))
        axes = [i for i in range(3) if i != axis]
        if obj['export_group'] == 'Artwork': axes = [0, 2]
        for li in face.loop_indices:
            p = obj.data.vertices[obj.data.loops[li].vertex_index].co
            a, b = axes
            u, v = (p[a]-lo[a])/extent[a], (p[b]-lo[b])/extent[b]
            # Flip V to Blender convention; rect is recorded in glTF convention.
            layer.data[li].uv = (u0+u*(u1-u0), 1-(v1-v*(v1-v0)))
    obj.data.materials.clear()
    obj.data.materials.append(MATERIALS['HallGlass' if obj['export_group'] == 'Glass' else 'HallOpaque'])
    for face in obj.data.polygons: face.material_index = 0


def patch_glb(path):
    raw = path.read_bytes(); n = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+n]); tail = raw[20+n:]
    doc['images'] = [{'uri': 'hallkit_palette.png'}]; doc['textures'] = [{'source': 0}]
    has_glass = any(n.get('name', '').startswith('EXPORT_Glass') for n in doc['nodes'])
    doc['materials'] = [{'name': 'HallOpaque'}] + ([{'name': 'HallGlass'}] if has_glass else [])
    for node in doc['nodes']:
        if 'mesh' not in node: continue
        group = node['name'].removeprefix('EXPORT_').split('.')[0]
        node['name'] = group
        for prim in doc['meshes'][node['mesh']]['primitives']:
            prim['material'] = 1 if group == 'Glass' else 0
    for mat in doc['materials']:
        glass = mat['name'] == 'HallGlass'
        mat['pbrMetallicRoughness'] = {'baseColorTexture': {'index': 0},
              'baseColorFactor': [1, 1, 1, .14 if glass else 1],
              'metallicFactor': 0, 'roughnessFactor': .16 if glass else .78}
        mat['alphaMode'] = 'BLEND' if glass else 'OPAQUE'
        mat['doubleSided'] = glass
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    path.write_bytes(struct.pack('<III', 0x46546C67, 2, 20+len(encoded)+len(tail)) +
                     struct.pack('<II', len(encoded), 0x4E4F534A) + encoded + tail)


def import_config(path):
    dest = Path(str(path)+'.import')
    if dest.exists(): return
    template = (ROOT/'assets/rooms/deluxe_room_10/sofa.glb.import').read_text()
    template = re.sub(r'uid="[^"]+"\n', '', template)
    relative = 'res://' + str(path.relative_to(ROOT))
    template = template.replace('res://assets/rooms/deluxe_room_10/sofa.glb', relative)
    target = 'res://.godot/imported/'+path.name+'-'+hashlib.md5(relative.encode()).hexdigest()+'.scn'
    template = re.sub(r'res://\.godot/imported/sofa\.glb-[^\"]+\.scn', target, template)
    dest.write_text(template)


def texture_import_config():
    dest = OUT/'hallkit_palette.png.import'
    if dest.exists(): return
    template = (ROOT/'assets/rooms/basic_room/room_albedo_ao.png.import').read_text()
    template = re.sub(r'uid="[^"]+"\n', '', template)
    relative = 'res://assets/rooms/_shared/shell_hall/hallkit_palette.png'
    target = 'res://.godot/imported/hallkit_palette.png-'+hashlib.md5(relative.encode()).hexdigest()+'.ctex'
    template = template.replace('res://assets/rooms/basic_room/room_albedo_ao.png', relative)
    template = re.sub(r'res://\.godot/imported/room_albedo_ao\.png-[^\"]+\.ctex', target, template)
    template = re.sub(r'compress/mode=\d+', 'compress/mode=2', template)
    template = template.replace('mipmaps/generate=false', 'mipmaps/generate=true')
    dest.write_text(template)


def export(name):
    objects = parts(name)
    for obj in objects: map_uv(obj)
    copies = []
    for group in sorted({o['export_group'] for o in objects}):
        bpy.ops.object.select_all(action='DESELECT')
        group_copies = []
        for obj in objects:
            if obj['export_group'] != group: continue
            copy = obj.copy(); copy.data = obj.data.copy()
            for layer in list(copy.data.uv_layers):
                if layer.name != 'HallPalette': copy.data.uv_layers.remove(layer)
            bpy.context.scene.collection.objects.link(copy)
            copy.select_set(True); group_copies.append(copy)
        bpy.context.view_layer.objects.active = group_copies[0]
        if len(group_copies) > 1: bpy.ops.object.join()
        joined = bpy.context.object
        joined.name = 'EXPORT_' + group
        copies.append(joined)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in copies: obj.select_set(True)
    path = OUT/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                             export_yup=True, export_normals=True, export_texcoords=True,
                             export_materials='PLACEHOLDER', export_animations=False,
                             export_cameras=False, export_lights=False, export_extras=False)
    for obj in copies: bpy.data.objects.remove(obj, do_unlink=True)
    patch_glb(path); import_config(path)
    result = glb_stats(path)
    item = {k: v for k, v in KITS[name].items() if k != 'collection'}
    item.update(result); item['file'] = name+'.glb'
    item['provenance'] = 'provenance/'+name+'/reuse_provenance.json'
    item['pivot'] = 'back mounting plane Z=0, centre Y=0' if item['family'] in ['sconce', 'frames'] else 'floor Y=0, horizontal source centre'
    item['parts'] = [{'name': o.name, 'source_part': o['source_part'],
                     'palette_slot': o['palette_slot'], 'export_group': o['export_group']}
                    for o in objects]
    dump(OUT/item['provenance'], {'author': '黄忠', 'virtual_user_id': '5281cd25-6a49-4df8-9802-f3e534956e80',
         'task': 'SGODOT-324', 'baseline_commit': BASELINE, 'asset': item,
         'sources': {s: SOURCES[s] for s in item['sources']},
         'texture_change': 'All runtime UVs remapped to one provisional Basic Room swatch atlas; no source atlas retained.',
         'source_mesh_rule': 'Evaluated named Blender geometry checked against source GLB dimensions and triangle count before editing.'})
    return item


def main():
    global BASELINE
    BASELINE = 'fadcaa195f5bb34229fba3995b27c5808ff34089'
    for path in [OUT, SOURCE]: path.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    make_furniture(); make_frames(); make_displays(); atlas(); texture_import_config()
    assets = [export(name) for name in KITS]
    dump(OUT/'asset_stats.json', {'task': 'SGODOT-324', 'status': 'provisional_reuse_kit',
         'families': 8, 'assets': assets, 'unique_triangles': sum(a['triangles'] for a in assets),
         'unique_surfaces': sum(a['surfaces'] for a in assets), 'atlas': 'hallkit_palette.png',
         'materials': 'One opaque material; one shared transparent glass material (same atlas).',
         'character_height_m': H, 'seat_height_m': SEAT})
    dump(OUT/'source_measurements.json', SOURCES)
    dump(OUT/'table_candidates.json', {kit: glb_stats(ROOT/'assets/rooms'/kit/(asset+'.glb'))
          for kit, asset in [('bakery', 'cafe_table'), ('coffee_shop_0', 'round_table'), ('tavern', 'round_table')]})
    x = 0
    for asset in assets:
        root = bpy.data.objects.new(asset['name'], None)
        KITS[asset['name']]['collection'].objects.link(root)
        for obj in parts(asset['name']):
            if obj != root: obj.parent = root
        root.location = (x, 0, 1.5 if asset['family'] in ['sconce', 'frames'] else 0)
        x += asset['dimensions_xyz_m'][0] + .8
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'hallkit_324.blend'))
    print('HALLKIT_324_EXPORTED', len(assets), sum(a['triangles'] for a in assets))


if __name__ == '__main__': main()
