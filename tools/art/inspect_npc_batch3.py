"""CPU-only Blender source inspection; never modifies the original FBX files."""
import argparse
import json
import sys
from pathlib import Path

import bpy


def components(mesh):
    adjacency = [set() for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    remaining = set(range(len(adjacency)))
    groups = []
    while remaining:
        seen, todo = set(), [min(remaining)]
        while todo:
            i = todo.pop()
            if i in seen:
                continue
            seen.add(i)
            todo.extend(adjacency[i] - seen)
        remaining -= seen
        groups.append(seen)
    return groups


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime-root', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    args.out.mkdir(parents=True, exist_ok=True)
    for part in ['cloth36_npc_sigrid', 'hairhat51', 'hairhat36_npc_pip', 'cloth1_1', 'hairhat41_npc_auburn']:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        path = next((args.runtime_root / 'assets/avatar/source' / part).glob('*.fbx'))
        bpy.ops.import_scene.fbx(filepath=str(path))
        rows = []
        for obj in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
            mesh = obj.data
            mesh.calc_loop_triangles()
            groups = components(mesh)
            group_ids = {vi: i for i, group in enumerate(groups) for vi in group}
            uv = mesh.uv_layers.active
            row = {'name': obj.name, 'parent': obj.parent.name if obj.parent else None,
                   'parent_type': obj.parent_type, 'parent_bone': obj.parent_bone,
                   'matrix_local': [list(r) for r in obj.matrix_local],
                   'matrix_world': [list(r) for r in obj.matrix_world],
                   'vertices': [list(v.co) for v in mesh.vertices],
                   'vertex_groups': [g.name for g in obj.vertex_groups],
                   'weights': [[[g.group, g.weight] for g in v.groups] for v in mesh.vertices],
                   'triangles': [{'vertices': list(t.vertices), 'component': group_ids[t.vertices[0]],
                                  'uv': [list(uv.data[i].uv) for i in t.loops]} for t in mesh.loop_triangles],
                   'components': []}
            for i, group in enumerate(groups):
                positions = [mesh.vertices[v].co for v in group]
                tris = [t for t in row['triangles'] if t['component'] == i]
                uvs = [uv for t in tris for uv in t['uv']]
                row['components'].append({'id': i, 'vertices': len(group), 'triangles': len(tris),
                                          'bounds': [[min(p[a] for p in positions) for a in range(3)],
                                                     [max(p[a] for p in positions) for a in range(3)]],
                                          'uv_bounds': [[min(p[a] for p in uvs) for a in range(2)],
                                                        [max(p[a] for p in uvs) for a in range(2)]] if uvs else []})
            rows.append(row)
        (args.out / (part + '.json')).write_text(json.dumps(rows) + '\n')
        print('BATCH3_SOURCE', part, json.dumps([{k: r[k] for k in ['name', 'components']} for r in rows]), flush=True)


if __name__ == '__main__':
    main()
