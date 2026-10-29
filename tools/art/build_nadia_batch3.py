"""Nadia's cap and apron: replace Geometry/weight arrays within the original FBX container."""
import argparse
from array import array
import copy
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from io_scene_fbx import parse_fbx, encode_bin

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_resident_parts_284 import child, element, scalar, encoded, same, components

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'tools/art/source/npc_batch3'


def tile(index): return ((index + .5) / 16, .0625)


class Geometry:
    def __init__(self, obj, keep=None):
        self.obj = obj
        self.vertices, self.faces, self.uvs, self.normals, self.weights, self.labels = [], [], [], [], [], []
        mesh = obj.data
        keep = set(range(len(mesh.vertices))) if keep is None else keep
        ids = sorted(keep)
        remap = {old: new for new, old in enumerate(ids)}
        self.vertices = [tuple(mesh.vertices[i].co) for i in ids]
        self.weights = [{obj.vertex_groups[g.group].name: g.weight for g in mesh.vertices[i].groups} for i in ids]
        for face in mesh.polygons:
            if not all(i in keep for i in face.vertices): continue
            self.faces.append(tuple(remap[i] for i in face.vertices))
            self.uvs.append([(mesh.uv_layers.active.data[i].uv.x, .125 + .875 * mesh.uv_layers.active.data[i].uv.y) for i in face.loop_indices])
            self.normals.append([tuple(mesh.corner_normals[i].vector) for i in face.loop_indices])
        self.labels.append(('Retained original hair' if keep != set(range(len(mesh.vertices))) else 'Retained original shirt and shorts', list(range(len(ids)))))
        self.original_vertices = len(ids)
        self.base_vertices = [v.co.copy() for v in mesh.vertices]
        self.base_faces = [list(p.vertices) for p in mesh.polygons]
        self.bvh = BVHTree.FromPolygons(self.base_vertices, self.base_faces, all_triangles=False)
        self.base_weights = [{obj.vertex_groups[g.group].name: g.weight for g in v.groups} for v in mesh.vertices]

    def nearest_weights(self, position):
        point, normal, index, distance = self.bvh.find_nearest(Vector(position))
        ids = self.base_faces[index]
        pairs = [(i, 1 / max((self.base_vertices[i] - point).length, .01) ** 2) for i in ids]
        total = sum(w for _, w in pairs)
        weights = {}
        for i, contribution in pairs:
            for bone, weight in self.base_weights[i].items():
                weights[bone] = weights.get(bone, 0) + weight * contribution / total
        weights = dict(sorted(weights.items(), key=lambda p: -p[1])[:4])
        total = sum(weights.values())
        return {k: v / total for k, v in weights.items()} if total else {}

    def add(self, label, vertices, faces, color=0, weights=True):
        start = len(self.vertices)
        self.vertices.extend(vertices)
        self.faces.extend(tuple(start + i for i in f) for f in faces)
        self.uvs.extend([[tile(color)] * len(f) for f in faces])
        self.normals.extend([None] * len(faces))
        self.weights.extend(self.nearest_weights(p) if weights else {} for p in vertices)
        self.labels.append((label, list(range(start, len(self.vertices)))))

    def finish(self, texture):
        mesh = bpy.data.meshes.new('Nadia editable geometry')
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        uv = mesh.uv_layers.new(name='map1')
        for p, coords in zip(mesh.polygons, self.uvs):
            p.use_smooth = True
            for li, value in zip(p.loop_indices, coords): uv.data[li].uv = value
        mesh.update()
        normals = []
        for p, source in zip(mesh.polygons, self.normals):
            normals.extend(source if source else [tuple(mesh.corner_normals[i].vector) for i in p.loop_indices])
        mesh.normals_split_custom_set(normals)
        self.obj.data = mesh
        self.obj.vertex_groups.clear()
        for bone in sorted({b for weights in self.weights for b in weights}):
            group = self.obj.vertex_groups.new(name=bone)
            for i, weights in enumerate(self.weights):
                if bone in weights: group.add([i], weights[bone], 'REPLACE')
        for label, ids in self.labels:
            group = self.obj.vertex_groups.new(name='EDIT_' + label)
            group.add(ids, 1.0, 'REPLACE')
        mat = bpy.data.materials.new('Nadia single atlas')
        mat.use_nodes = True
        bs = mat.node_tree.nodes.get('Principled BSDF'); bs.inputs['Roughness'].default_value = .9
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image = bpy.data.images.load(str(texture))
        tex.image.pack()
        mat.node_tree.links.new(tex.outputs['Color'], bs.inputs['Base Color'])
        mesh.materials.clear(); mesh.materials.append(mat)
        return mesh


def write_fbx(source, dest, builder, rebuild_skin=False):
    tree, version = parse_fbx.parse(str(source))
    old = copy.deepcopy(tree)
    objects = child(tree, b'Objects').elems
    by_id = {e.props[0]: e for e in objects}
    connections = [c.props for c in child(tree, b'Connections').elems]
    model = next(e for e in objects if e.id == b'Model' and e.props[1].split(b'\x00')[0].decode() == builder.obj.name)
    geometry = next(by_id[c[1]] for c in connections if c[2] == model.props[0] and by_id.get(c[1]) and by_id[c[1]].id == b'Geometry')
    mesh = builder.obj.data
    indices, normals, uvs = array('i'), array('d'), array('d')
    for face in mesh.polygons:
        for j, li in enumerate(face.loop_indices):
            index = mesh.loops[li].vertex_index
            indices.append(index if j < len(face.loop_indices) - 1 else -index - 1)
            normals.extend(mesh.corner_normals[li].vector)
            uvs.extend(mesh.uv_layers.active.data[li].uv)
    normal_node = element(b'LayerElementNormal', 'I', [0], [element(b'Version', 'I', [101]), scalar(b'Name', b''), scalar(b'MappingInformationType', b'ByPolygonVertex'), scalar(b'ReferenceInformationType', b'Direct'), element(b'Normals', 'd', [normals])])
    uv_node = element(b'LayerElementUV', 'I', [0], [element(b'Version', 'I', [101]), scalar(b'Name', b'map1'), scalar(b'MappingInformationType', b'ByPolygonVertex'), scalar(b'ReferenceInformationType', b'Direct'), element(b'UV', 'd', [uvs])])
    material = element(b'LayerElementMaterial', 'I', [0], [element(b'Version', 'I', [101]), scalar(b'Name', b''), scalar(b'MappingInformationType', b'AllSame'), scalar(b'ReferenceInformationType', b'IndexToDirect'), element(b'Materials', 'i', [array('i', [0])])])
    layer = element(b'Layer', 'I', [0], [element(b'Version', 'I', [100])] + [element(b'LayerElement', elems=[scalar(b'Type', kind), element(b'TypedIndex', 'I', [0])]) for kind in [b'LayerElementNormal', b'LayerElementUV', b'LayerElementMaterial']])
    geometry.elems[:] = [element(b'Vertices', 'd', [array('d', (x for v in mesh.vertices for x in v.co))]), element(b'PolygonVertexIndex', 'i', [indices]), element(b'GeometryVersion', 'I', [124]), normal_node, uv_node, material, layer]
    changed_clusters = set()
    skins = [by_id[c[1]] for c in connections if c[2] == geometry.props[0] and by_id.get(c[1]) and by_id[c[1]].id == b'Deformer']
    for skin in skins:
        clusters = [by_id[c[1]] for c in connections if c[2] == skin.props[0] and by_id.get(c[1]) and by_id[c[1]].id == b'Deformer']
        for cluster in clusters:
            bone = next(by_id[c[1]] for c in connections if c[2] == cluster.props[0] and by_id.get(c[1]) and by_id[c[1]].id == b'Model')
            name = bone.props[1].split(b'\x00')[0].decode()
            extra = [(i, weights[name]) for i, weights in enumerate(builder.weights) if (rebuild_skin or i >= builder.original_vertices) and name in weights]
            if not extra and not rebuild_skin: continue
            if rebuild_skin:
                if not extra and not any(e.id == b'Indexes' for e in cluster.elems): continue
                for key, kind, values in [(b'Indexes','i',(i for i, _ in extra)), (b'Weights','d',(w for _, w in extra))]:
                    existing = next((e for e in cluster.elems if e.id == key), None)
                    values = array(kind, values)
                    if existing is None: cluster.elems.append(element(key, kind, [values]))
                    else: existing.props[0] = values
            else:
                child(cluster, b'Indexes').props[0].extend(i for i, _ in extra)
                child(cluster, b'Weights').props[0].extend(w for _, w in extra)
            changed_clusters.add(cluster.props[0])
    encode_bin.write(str(dest), encoded(tree), version)
    after, after_version = parse_fbx.parse(str(dest))
    assert after_version == version
    for a, b in zip(old.elems, after.elems):
        if a.id in [b'FileId', b'CreationTime']: continue
        if a.id != b'Objects': assert same(a, b), a.id; continue
        assert len(a.elems) == len(b.elems)
        for x, y in zip(a.elems, b.elems):
            if x.props[0] == geometry.props[0]:
                assert x.props == y.props
            elif x.props[0] in changed_clusters:
                assert x.props == y.props
                assert {e.id for e in y.elems} - {e.id for e in x.elems} <= {b'Indexes', b'Weights'}
                for u in x.elems:
                    v = child(y, u.id)
                    if u.id in [b'Indexes', b'Weights']:
                        if not rebuild_skin: assert list(v.props[0][:len(u.props[0])]) == list(u.props[0])
                    else: assert same(u, v)
            else: assert same(x, y), (x.id, x.props[:2])
    mesh.calc_loop_triangles()
    return {'triangles': len(mesh.loop_triangles), 'vertices': len(mesh.vertices), 'original_vertices_retained': builder.original_vertices,
            'original_node_names_hierarchy_transforms_axes_units_exact': True, 'connections_exact': True,
            'original_skin_weights_and_bind_matrices_exact': not rebuild_skin, 'original_bind_matrices_exact': True,
            'skin_weight_arrays_rebuilt': rebuild_skin, 'clusters_extended_for_new_geometry': len(changed_clusters),
            'other_objects_and_geometry_exact': True, 'sha256': hashlib.sha256(dest.read_bytes()).hexdigest()}


def load(source, name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.import_scene.fbx(filepath=str(source))
    return bpy.data.objects[name]


def cap(runtime):
    src = runtime / 'assets/avatar/source/hairhat41_npc_auburn/SM_hairHat41.fbx'
    dest = runtime / 'assets/avatar/source/hairhat41_npc_nadia_baker'
    obj = load(src, 'hairHat')
    builder = Geometry(obj, components(obj.data)[0])
    n = 32
    def ring(label, profile, color):
        verts = []
        for height, radius in profile:
            for i in range(n):
                angle = i * math.tau / n
                # Native head-bone coordinates are X-up, Y-forward, Z-side in cm.
                ripple = 1 + .018 * math.sin(8 * angle)
                verts.append((height, -6.5 + radius * math.cos(angle) * ripple, radius * 1.04 * math.sin(angle) * ripple))
        faces = []
        for k in range(len(profile) - 1):
            for i in range(n):
                j = (i + 1) % n
                faces.append((k*n+i, k*n+j, (k+1)*n+j, (k+1)*n+i))
        builder.add(label, verts, faces, color, weights=False)
    ring('Low linen band', [(31.8, 26.3), (32.1, 27.2), (37.8, 27.5), (38.3, 26.5)], 1)
    ring('Soft pleated baker crown', [(37.7, 27.1), (41.0, 30.0), (46.0, 30.8), (50.2, 26.8), (52.2, 18), (52.5, 8), (52.3, .01)], 0)
    ring('Lower stitched piping', [(32.0, 27.2), (32.5, 27.6), (33.0, 27.2)], 2)
    builder.finish(dest / 'T_nadia_baker_hairHat41_D.png')
    report = write_fbx(src, dest / src.name, builder)
    report.update(base='hairhat41_npc_auburn', base_triangles=2312, triangle_delta=report['triangles'] - 2312)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'nadia-baker-hat.blend'))
    return report


def apron(runtime):
    src = runtime / 'assets/avatar/source/cloth1_1/SK_dt_skin01.fbx'
    dest = runtime / 'assets/avatar/source/cloth1_1_npc_nadia'
    obj = load(src, 'cloth')
    builder = Geometry(obj)
    def front_depth(x, y):
        point, normal, index, distance = builder.bvh.ray_cast(Vector((x, y, 45)), Vector((0, 0, -1)), 80)
        depth = (point.z if point is not None else 11.0) + 2.0
        # The shirt tail flares beyond the shorts; the apron must bridge it.
        return max(depth, 16.8) if y <= 94 else depth
    # A gridded bib/skirt follows the original shirt surface and bends with its skin.
    rows = [(64, 16.5), (68, 17), (76, 16.5), (85, 15.4), (94, 13.2), (101, 10.1), (110, 8.8)]
    vertices = []
    for y, width in rows:
        for column in range(9):
            x = -width + column * width / 4
            vertices.append((x, y, front_depth(x, y) + (.4 * math.cos(x * .6) if y < 85 else 0)))
    faces = [(r*9+c, r*9+c+1, (r+1)*9+c+1, (r+1)*9+c) for r in range(len(rows)-1) for c in range(8)]
    builder.add('Cream apron bib and skirt', vertices, faces, 4)
    def ribbon(label, points, width, color=0):
        verts = []
        for x, y, z in points: verts.extend([(x-width/2, y, z), (x+width/2, y, z)])
        faces = [(i*2, i*2+1, i*2+3, i*2+2) for i in range(len(points)-1)]
        # Give exposed strips a rear face; cull_back is retained on the base shader.
        faces += [tuple(reversed(f)) for f in faces.copy()]
        builder.add(label, verts, faces, color)
    for sign in [-1, 1]:
        x = sign * 7.2
        ribbon('Shoulder strap ' + str(sign), [(x, 109, front_depth(x,109)+.2), (x,116,front_depth(x,116)+.5),
               (x,122,5), (x,123,-1), (x,119,-7), (x,110,-10), (sign*3,99,-11), (-sign*6,91,-12.5)], 3, 0)
    # Waist ribbon wraps around the sides; short crossed ends read as tied cloth.
    verts = []
    for y in [87.5, 90]:
        for i in range(33):
            angle = i * math.tau / 32
            verts.append((16.1*math.sin(angle), y, 13.6*math.cos(angle)))
    faces = [(i, i+1, 33+i+1, 33+i) for i in range(32)]
    builder.add('Waist ribbon', verts, faces, 0)
    ribbon('Left tie end', [(0,89,-14),(-3,85,-14.3),(-5,80,-14.5)], 2.5, 1)
    ribbon('Right tie end', [(0,89,-14),(3,85,-14.3),(5,81,-14.5)], 2.5, 1)
    # Empty rounded chest pocket, intentionally without produce or tools.
    outline = [(-5.2,101),(-5.2,94),(-3.8,92.7),(3.8,92.7),(5.2,94),(5.2,101)]
    pocket_depth = max(front_depth(x,y) for x,y in outline) + 1.0
    pocket = [(x,y,pocket_depth) for x,y in outline]
    builder.add('Empty chest pocket', pocket, [tuple(range(6))], 5)
    ribbon('Pocket top hem', [(0,100.7,pocket_depth+.2), (0,101.4,pocket_depth+.2)], 10.6, 0)
    builder.finish(dest / 'T_nadia_apron_cloth01_D.png')
    report = write_fbx(src, dest / src.name, builder)
    report.update(base='cloth1_1', base_triangles=1629, triangle_delta=report['triangles'] - 1629)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'nadia-apron.blend'))
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime-root', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    report = {'cap': cap(args.runtime_root), 'apron': apron(args.runtime_root)}
    (OUT / 'nadia-geometry-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print('NADIA_GEOMETRY', json.dumps(report), flush=True)


if __name__ == '__main__': main()
