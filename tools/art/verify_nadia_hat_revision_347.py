"""Verify the cap-only drop/fit against v1, including unchanged hair and node data."""
import argparse
import json
from pathlib import Path
import sys
import numpy as np
import bpy
from io_scene_fbx import parse_fbx

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_resident_parts_284 import child, same

parser = argparse.ArgumentParser()
parser.add_argument('--before', type=Path, required=True)
parser.add_argument('--after', type=Path, required=True)
parser.add_argument('--blend', type=Path, required=True)
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
old, old_version = parse_fbx.parse(str(args.before))
new, new_version = parse_fbx.parse(str(args.after))
assert old_version == new_version
old_geometry = next(n for n in child(old, b'Objects').elems if n.id == b'Geometry')
new_geometry = next(n for n in child(new, b'Objects').elems if n.id == b'Geometry')
before = np.array(child(old_geometry, b'Vertices').props[0]).reshape(-1, 3)
after = np.array(child(new_geometry, b'Vertices').props[0]).reshape(-1, 3)
assert before.shape == after.shape == (751, 3)
bpy.ops.wm.open_mainfile(filepath=str(args.blend))
obj = bpy.data.objects['hairHat']
hair_group = obj.vertex_groups['EDIT_Retained original hair'].index
hair = [v.index for v in obj.data.vertices if any(g.group == hair_group for g in v.groups)]
assert hair == list(range(303))
hat = np.ones(len(before), dtype=bool)
hat[hair] = False
delta = after - before
assert np.array_equal(delta[hair], np.zeros((303, 3)))
assert np.array_equal(delta[hat, 0], np.full(448, -2.0))
mouth = np.zeros(len(before), dtype=bool)
mouth[303:367] = True
mouth[655:751] = True
assert np.array_equal(delta[hat & ~mouth, 1:], np.zeros((288, 2)))
assert np.all(np.linalg.norm(after[mouth, 1:] - [-6.5, 0], axis=1) <
              np.linalg.norm(before[mouth, 1:] - [-6.5, 0], axis=1))
assert np.max(np.linalg.norm(delta[mouth, 1:], axis=1)) < 2.2
assert np.array_equal(after, np.array([list(v.co) for v in obj.data.vertices]))
indices = np.array(child(old_geometry, b'PolygonVertexIndex').props[0])
hair_loops = np.where(indices < 0, -indices - 1, indices) < 303
old_normals = np.array(child(child(old_geometry, b'LayerElementNormal'), b'Normals').props[0]).reshape(-1, 3)
new_normals = np.array(child(child(new_geometry, b'LayerElementNormal'), b'Normals').props[0]).reshape(-1, 3)
assert np.array_equal(old_normals[hair_loops], new_normals[hair_loops])
differences = []
for a, b in zip(old_geometry.elems, new_geometry.elems):
    if a.id not in [b'Vertices', b'LayerElementNormal'] and not same(a, b):
        differences.append(a.id.decode())
assert not differences, differences
old_geometry.elems[:] = [n for n in old_geometry.elems if n.id not in [b'Vertices', b'LayerElementNormal']]
new_geometry.elems[:] = [n for n in new_geometry.elems if n.id not in [b'Vertices', b'LayerElementNormal']]
ignored_metadata = {b'FileId', b'CreationTime'}
old.elems[:] = [n for n in old.elems if n.id not in ignored_metadata]
new.elems[:] = [n for n in new.elems if n.id not in ignored_metadata]
assert same(old, new), 'Non-position FBX data changed'
report = {
    'baseline': 'ad751863', 'hair_vertices_unchanged': 303, 'hat_vertices_translated': 448,
    'cap_drop_cm': 2.0, 'mouth_vertices_inset': 160, 'mouth_radius_inset_cm': 2.0,
    'native_axis': 'X-up, cm', 'crown_shape_exact': True,
    'hair_positions_and_normals_exact': True, 'indices_uv_material_assignments_exact': True,
    'nodes_hierarchy_transforms_axes_units_connections_exact': True,
    'blend_vertex_positions_match_fbx': True, 'triangles': 1296, 'triangle_delta_from_v1': 0,
    'encoder_metadata_excluded': ['FileId', 'CreationTime'],
}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('NADIA_HAT_REVISION', json.dumps(report))
