"""Blender source comparison: only roof parts may differ from merged v9.

Run with Blender --background --python-exit-code 1 --python this_file.
The baseline is recovered from the pinned merge, never another worktree.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import bpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path[:0] = [str(ROOT/'tools/art'), str(HERE)]
import museum_roof
BASE = '02d5534768fc1a5557feaecb705b8f445562fd6b'
OUT = ROOT/'output/alcatraz-roof-424'
OUT.mkdir(parents=True, exist_ok=True)
baseline = OUT/'baseline-source.blend'
baseline.write_bytes(subprocess.check_output(['git', 'show', BASE+':'+str((HERE/'alcatraz_blockout.blend').relative_to(ROOT))]))


def fingerprint(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    rows = {}
    roof = []
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and obj in bpy.data.collections['alc_museum'].objects.values() and museum_roof.is_roof_part(obj.name):
            roof.append(obj.name)
            continue
        row = {'name': obj.name, 'type': obj.type, 'matrix': [list(r) for r in obj.matrix_world],
               'collections': sorted(c.name for c in obj.users_collection),
               'instance': obj.instance_collection.name if obj.instance_collection else None}
        if obj.type == 'MESH':
            mesh = obj.data
            row.update(vertices=[list(v.co) for v in mesh.vertices], faces=[list(p.vertices) for p in mesh.polygons],
                       uv={u.name: [list(x.uv) for x in u.data] for u in mesh.uv_layers},
                       materials=[list(m.diffuse_color) for m in mesh.materials],
                       material_indices=[p.material_index for p in mesh.polygons],
                       modifiers=[{'type': m.type, 'width': getattr(m, 'width', None),
                                   'segments': getattr(m, 'segments', None)} for m in obj.modifiers])
        rows[obj.name] = hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest()
    return rows, sorted(roof)


before, old_roof = fingerprint(baseline)
after, new_roof = fingerprint(HERE/'alcatraz_blockout.blend')
assert before == after, {'removed': list(before.keys()-after.keys()), 'added': list(after.keys()-before.keys()),
                         'changed': [n for n in before.keys() & after.keys() if before[n] != after[n]]}
collection = bpy.data.collections['alc_museum']
assert not any(o.type == 'FONT' for o in collection.objects)
assert len([o for o in collection.objects if o.name.startswith('museum_pictogram_')]) == 4
assert len([o for o in collection.objects if o.name.startswith('museum_skylight_') and o.name.endswith('_curb')]) == 3
assert len([o for o in collection.objects if o.name.startswith('roof_vent_') and o.name.endswith('_body')]) == 2
report = {'passed': True, 'baseline': BASE, 'unchanged_nonroof_objects_and_instances': len(before),
          'comparison': 'Named objects, vertices, faces, UVs, materials, bevels, transforms, collection membership and assembly instances',
          'previous_roof_parts': old_roof, 'current_roof_parts': new_roof,
          'skylights': 3, 'vents': 2, 'blank_sign_and_four_pictogram_parts_preserved': True,
          'blender': bpy.app.version_string}
(OUT/'source-verification.json').write_text(json.dumps(report, indent=2)+'\n')
print('ROOF_SOURCE_PASS', len(before), 'other objects and instances identical')
