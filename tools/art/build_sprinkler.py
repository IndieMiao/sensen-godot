"""SGODOT-244 sprinkler; Blender 5.2, metres, Godot Y up and +Z front.

Reuses the greenhouse's vertex-paint helpers. Only sprinkler.glb and its manifest
entry are exported. Head geometry is local to (0, .42, 0); no runtime integration.
"""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_greenhouse as g
from verify_chef_sign import load_glb, accessor

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'assets/farm/art'
SOURCE = ROOT/'tools/art/source/sprinkler_244'
HEAD = (0, .42, 0)
PALETTE = {
    'stone': 'b4b8b1', 'stone_light': 'c5c9c1', 'stone_shade': 'a0a69d',
    'sage': 'a6b397', 'sage_light': 'b4c1a5', 'sage_shade': '8d9c80',
    'brass': 'e8ce5b', 'brass_light': 'f5dd7c', 'brass_shade': 'c4ac46',
    'water': '8cc7f2', 'water_light': 'a8d5f5', 'water_shade': '74b4e3',
    'nozzle_dot': '665d36',
}
ARM = [(.059, .410, 0), (.089, .390, 0), (.116, .389, 0),
       (.145, .408, 0), (.160, .427, 0)]
ARM_RADIUS = .020


def colour_faces(obj, base, light, shade):
    obj.data.materials.clear()
    for colour in [base, light, shade]: obj.data.materials.append(g.MATS[colour])
    for face in obj.data.polygons:
        face.material_index = 1 if face.normal.z > .45 else 2 if face.normal.z < -.45 else 0


def capped_profile(name, profile, colour, segments=12, at=(0, 0, 0)):
    return g.lathe(name, profile, colour, segments=segments, at=at)


def build_base():
    obj = capped_profile('Round edged stone mounting pad',
                         [(.110, 0), (.121, .004), (.125, .012),
                          (.125, .028), (.121, .039), (.110, .047)], 'stone', 16)
    colour_faces(obj, 'stone', 'stone_light', 'stone_shade')
    obj = capped_profile('Stout sage green riser',
                         [(.058, .036), (.065, .050), (.055, .362), (.049, .382)], 'sage', 10)
    colour_faces(obj, 'sage', 'sage_light', 'sage_shade')


def build_head():
    obj = capped_profile('Rounded yellow brass rotating hub',
                         [(.060, .372), (.070, .384), (.070, .432), (.060, .442)], 'brass', 12)
    colour_faces(obj, 'brass', 'brass_light', 'brass_shade')
    for sign, label in [(-1, 'Left'), (1, 'Right')]:
        points = [(sign*x, y, z) for x, y, z in ARM]
        obj = g.curved_tube(label+' short down then up curved arm', points, ARM_RADIUS, 'brass', sides=8)
        colour_faces(obj, 'brass', 'brass_light', 'brass_shade')
        # A rounded axial profile; the small centre disk is coplanar paint, no hole.
        obj = capped_profile(label+' round nozzle with painted centre',
                             [(.020, 0), (.025, .007), (.026, .023),
                              (.021, .034), (.006, .034)], 'brass', 10)
        colour_faces(obj, 'brass', 'brass_light', 'brass_shade')
        obj.data.materials.append(g.MATS['nozzle_dot'])
        for face in obj.data.polygons:
            if all(abs(obj.data.vertices[v].co.z-.034)<1e-6 and
                   obj.data.vertices[v].co.xy.length<.00601 for v in face.vertices):
                face.material_index = 3
        obj.location = g.v((sign*.158, .427, 0))
        axis = g.v((sign*.98, .20, 0)).normalized()
        obj.rotation_euler = axis.to_track_quat('Z', 'Y').to_euler()
    # Eight-sided teardrop; a single top vertex avoids a collapsed ring.
    rings = [(.020, .433), (.043, .441), (.050, .457), (.033, .478), (.013, .499)]
    vertices = [(r*math.cos(i*math.tau/8), y, r*math.sin(i*math.tau/8))
                for r, y in rings for i in range(8)]
    vertices.append((0, .517, 0))
    faces = [tuple(reversed(range(8)))]
    for j in range(len(rings)-1):
        for i in range(8):
            a, b = j*8+i, j*8+(i+1)%8
            faces.append((a, b, b+8, a+8))
    last = (len(rings)-1)*8
    faces += [(last+i, last+(i+1)%8, len(vertices)-1) for i in range(8)]
    obj = g.mesh('Blue water droplet cap', vertices, faces, 'water', True)
    colour_faces(obj, 'water', 'water_light', 'water_shade')


def export_part(collection, name, material, pivot):
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    bpy.ops.object.select_all(action='DESELECT')
    copies = []
    part_counts = []
    for source in collection.objects:
        data = bpy.data.meshes.new_from_object(source.evaluated_get(deps), depsgraph=deps)
        data.transform(source.matrix_world)
        data.calc_loop_triangles()
        part_counts.append({'name': source.name, 'triangles': len(data.loop_triangles)})
        obj = bpy.data.objects.new(source.name+' export', data)
        bpy.context.scene.collection.objects.link(obj)
        obj.select_set(True); copies.append(obj)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    obj.data.name = 'sprinkler_'+name+'_mobile'
    tri = obj.modifiers.new('Fixed export triangles', 'TRIANGULATE')
    tri.quad_method = 'FIXED'; tri.ngon_method = 'CLIP'
    bpy.ops.object.modifier_apply(modifier=tri.name)
    colours = obj.data.color_attributes.new(name='Color', type='FLOAT_COLOR', domain='CORNER')
    obj.data.color_attributes.active_color = colours
    obj.data.color_attributes.render_color_index = 0
    for face in obj.data.polygons:
        colour = obj.data.materials[face.material_index].diffuse_color
        for index in face.loop_indices: colours.data[index].color = colour
    obj.data.materials.clear(); obj.data.materials.append(material)
    for face in obj.data.polygons: face.material_index = 0
    for uv in list(obj.data.uv_layers): obj.data.uv_layers.remove(uv)
    obj.data.transform(Matrix.Translation(-g.v(pivot)))
    obj.location = g.v(pivot)
    return obj, part_counts


def canonicalize(path):
    raw = bytearray(path.read_bytes())
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+size])
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            acc = doc['accessors'][primitive['indices']]
            view = doc['bufferViews'][acc['bufferView']]
            offset = 28+size+view.get('byteOffset', 0)+acc.get('byteOffset', 0)
            fmt = '<'+{5121: 'B', 5123: 'H', 5125: 'I'}[acc['componentType']]*acc['count']
            indices = struct.unpack_from(fmt, raw, offset)
            triangles = sorted(tuple(indices[i:i+3]) for i in range(0, len(indices), 3))
            struct.pack_into(fmt, raw, offset, *(v for t in triangles for v in t))
    path.write_bytes(raw)


def actual_stats(path):
    doc, data = load_glb(path)
    vertices, parts, triangles = [], {}, 0
    for node in doc['nodes']:
        if 'mesh' not in node: continue
        prim = doc['meshes'][node['mesh']]['primitives']
        assert len(prim) == 1
        points = accessor(doc, data, prim[0]['attributes']['POSITION'])
        offset = node.get('translation', [0, 0, 0])
        world = [tuple(p[i]+offset[i] for i in range(3)) for p in points]
        vertices.extend(world)
        count = len(accessor(doc, data, prim[0]['indices']))//3
        parts[node['name']] = {'triangles': count, 'surfaces': 1, 'pivot': offset}
        triangles += count
    bounds = [[min(v[i] for v in vertices) for i in range(3)],
              [max(v[i] for v in vertices) for i in range(3)]]
    assert triangles <= 800, triangles
    assert .51 <= bounds[1][1] <= .53
    assert max(math.hypot(p[0], p[2]) for p in vertices) <= .20
    return {'triangles': triangles, 'surfaces': 2, 'bounds': bounds, 'parts': parts,
            'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    SOURCE.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    for name, colour in PALETTE.items():
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*g.rgb(colour), 1)
        mat.use_nodes = True
        shader = mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = mat.diffuse_color
        shader.inputs['Roughness'].default_value = .9
        g.MATS[name] = mat
    collections = {}
    for name, build in [('base', build_base), ('head', build_head)]:
        collection = bpy.data.collections.new('Sprinkler_'+name)
        bpy.context.scene.collection.children.link(collection)
        collections[name] = collection; g.CURRENT = collection; build()
    runtime = bpy.data.materials.new('Farm vertex paint')
    runtime.use_nodes = True; runtime.use_backface_culling = True
    shader = runtime.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = .9
    shader.inputs['Specular IOR Level'].default_value = .18
    vertex = runtime.node_tree.nodes.new('ShaderNodeVertexColor'); vertex.layer_name = 'Color'
    runtime.node_tree.links.new(vertex.outputs['Color'], shader.inputs['Base Color'])
    exports, source_parts = [], {}
    for name, collection in collections.items():
        obj, counts = export_part(collection, name, runtime, HEAD if name == 'head' else (0, 0, 0))
        exports.append(obj); source_parts[name] = counts
    marker = bpy.data.objects.new('spray_origin', None)
    bpy.context.scene.collection.objects.link(marker)
    marker.location = g.v(HEAD)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in exports+[marker]: obj.select_set(True)
    path = OUT/'sprinkler.glb'
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
        export_yup=True, export_materials='EXPORT', export_texcoords=False, export_tangents=False,
        export_attributes=False, export_cameras=False, export_lights=False, export_animations=False)
    canonicalize(path)
    entry = {**actual_stats(path), 'generator': 'tools/art/build_sprinkler.py', 'triangle_limit': 800,
             'head_pivot': list(HEAD), 'spray_origin': list(HEAD), 'front': '+Z',
             'pivot': 'plot bed centre; place root at BED_H=0.15 m; unit scale',
             'material': 'FarmArt.material() on base and head; two meshes, do not use FarmArt.mesh_for()',
             'art_revision': 'v1.2',
             'arm_diameter_m': ARM_RADIUS*2, 'stone_diameter_m': .25, 'cap_diameter_m': .10,
             'riser_diameter_base_m': .13, 'riser_diameter_top_m': .11,
             'hub_diameter_m': .14, 'hub_height_m': .07, 'nozzle_diameter_m': .052,
             'palette_srgb': PALETTE, 'arm_centreline_right_m': ARM,
             'nozzle_dot': 'one coplanar vertex-colour centre dot per nozzle; no drilled geometry or separate mesh',
             'runtime_note': 'head static by default; consumer may rotate around Y for 2-3 s on watering / tap',
             'integration_note': 'On integration change P0FarmFacilities.HEAD from (0, 0.55, 0) to (0, 0.42, 0); no gameplay edit in this art branch.'}
    manifest = json.loads((OUT/'manifest.json').read_text())
    manifest['assets']['sprinkler'] = entry
    (OUT/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    (SOURCE/'source_parts.json').write_text(json.dumps(source_parts, indent=2)+'\n')
    for obj in exports: bpy.data.objects.remove(obj, do_unlink=True)
    marker.empty_display_type = 'ARROWS'; marker.empty_display_size = .08
    for name, collection in collections.items():
        root = bpy.data.objects.new(name, None); collection.objects.link(root)
        root.location = g.v(HEAD if name == 'head' else (0, 0, 0))
        bpy.context.view_layer.update()
        for obj in list(collection.objects):
            if obj == root: continue
            world = obj.matrix_world.copy(); obj.parent = root; obj.matrix_world = world
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'sprinkler_244.blend'))
    print('SPRINKLER_EXPORTED', json.dumps(entry))


if __name__ == '__main__': main()
