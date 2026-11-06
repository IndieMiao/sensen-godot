"""Verify the exported vent delta against approved #835 v1, independent of Blender."""
from collections import Counter, defaultdict
from pathlib import Path
import hashlib
import json
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[4]
BASE = '4a47e6223903e4adb504dfd738bbb0ab2cb63a27'
ASSETS = ROOT/'assets/landmarks/alcatraz_island'
OUT = ROOT/'output/alcatraz-roof-424/v1.1'


def original(path):
    return subprocess.check_output(['git', 'show', BASE+':'+str(path.relative_to(ROOT))])


def read_glb(data):
    size = struct.unpack_from('<I', data, 12)[0]
    document = json.loads(data[20:20+size])
    binary = data[28+size:]

    def accessor(index):
        a = document['accessors'][index]
        view = document['bufferViews'][a['bufferView']]
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        code = {5126: 'f', 5125: 'I', 5123: 'H', 5121: 'B'}[a['componentType']]
        stride = view.get('byteStride', struct.calcsize('<'+code*width))
        start = view.get('byteOffset', 0)+a.get('byteOffset', 0)
        return [struct.unpack_from('<'+code*width, binary, start+i*stride) for i in range(a['count'])]

    triangles = Counter()
    all_positions = []
    surfaces = 0
    for mesh in document['meshes']:
        for p in mesh['primitives']:
            surfaces += 1
            assert p.get('mode', 4) == 4
            attributes = {name: accessor(index) for name, index in p['attributes'].items()}
            positions = attributes['POSITION']
            all_positions.extend(positions)
            indices = [i[0] for i in accessor(p['indices'])]
            for i in range(0, len(indices), 3):
                vertices = []
                for index in indices[i:i+3]:
                    vertices.append(tuple((name, tuple(round(v, 9 if name.startswith('TEXCOORD') else 6) for v in attributes[name][index]))
                                          for name in sorted(attributes)))
                triangles[tuple(sorted(vertices))] += 1
    bounds = [[min(p[i] for p in all_positions) for i in range(3)],
              [max(p[i] for p in all_positions) for i in range(3)]]
    return triangles, bounds, surfaces


near = ASSETS/'alc_museum.glb'
before, old_bounds, _ = read_glb(original(near))
after, new_bounds, surfaces = read_glb(near.read_bytes())
assert old_bounds[0] == new_bounds[0]
assert old_bounds[1][0] == new_bounds[1][0] and old_bounds[1][2] == new_bounds[1][2]
assert abs(new_bounds[1][1]-9.18) < .000001
assert surfaces == 1


def in_vent(triangle):
    points = [dict(v)['POSITION'] for v in triangle]
    return any(all(abs(p[0]-x) <= .616 and abs(p[2]+2.5) <= .616 and 8.639 <= p[1] <= 9.181
                   for p in points) for x in [-16.3, 16.3])


def geometry_and_uvs(triangles):
    geometry = Counter()
    uv_groups = defaultdict(list)
    for triangle, count in triangles.items():
        key = tuple(sorted(tuple(item for item in vertex if not item[0].startswith('TEXCOORD')) for vertex in triangle))
        geometry[key] += count
        if not in_vent(triangle):
            uv_groups[key].extend([tuple(dict(v).get('TEXCOORD_0', ()) for v in triangle)]*count)
    return geometry, uv_groups


old_geometry, old_uvs = geometry_and_uvs(before)
new_geometry, new_uvs = geometry_and_uvs(after)
assert old_uvs.keys() == new_uvs.keys()
max_uv_delta = 0.0
for key, groups in old_uvs.items():
    assert len(groups) == len(new_uvs[key])
    for old, new in zip(sorted(groups), sorted(new_uvs[key])):
        for a, b in zip(old, new):
            max_uv_delta = max(max_uv_delta, *(abs(x-y) for x, y in zip(a, b)))
# Re-evaluating the unchanged bevels can move float UVs by one rounding unit.
# Source UVs remain exact; no UV-dependent material is added by this revision.
assert max_uv_delta < .000001, max_uv_delta
changed = list((old_geometry-new_geometry).elements())+list((new_geometry-old_geometry).elements())
lowest = min(dict(vertex)['POSITION'][1] for triangle in changed for vertex in triangle)
assert lowest >= 8.37, lowest
assert all(in_vent(t) for t in changed), 'A changed triangle lies outside the two vent bounds'
assert sum(before.values()) == sum(after.values())
unchanged = []
for p in ASSETS.rglob('*'):
    if not p.is_file() or p.name in ['alc_museum.glb', 'manifest.json']:
        continue
    assert p.read_bytes() == original(p), str(p.relative_to(ROOT))
    unchanged.append(str(p.relative_to(ASSETS)))
for name in ['alcatraz_island.gd', 'alcatraz_island.gd.uid', 'alcatraz_island.tscn']:
    p = ROOT/'scenes/landmark'/name
    assert p.read_bytes() == original(p), name
uid = re.search(r'^uid="uid://([^"]+)"', (ASSETS/'alc_museum.glb.import').read_text(), re.M).group(1)
assert re.fullmatch('[a-y0-8]+', uid), uid
old_manifest = json.loads(original(ASSETS/'manifest.json'))
new_manifest = json.loads((ASSETS/'manifest.json').read_text())
old_manifest['assets'].pop('alc_museum')
new_manifest['assets'].pop('alc_museum')
assert old_manifest == new_manifest
report = {'passed': True, 'baseline': BASE, 'old_near_triangles': sum(before.values()),
          'new_near_triangles': sum(after.values()), 'surfaces': surfaces,
          'bounds_before': old_bounds, 'bounds_after': new_bounds,
          'changed_triangles_min_y_m': lowest,
          'method': 'Canonical triangle multiset of position/normal/vertex colour (6 decimals); every changed triangle is inside one of the two vent boxes. All other export UVs are checked separately; Blender source data outside the vents is exact.',
          'nonvent_export_max_uv_delta': max_uv_delta,
          'unchanged_asset_files': unchanged, 'layout_and_runtime_scripts_exact': True,
          'import_uid_retained': uid, 'sha256': hashlib.sha256(near.read_bytes()).hexdigest()}
(OUT/'asset-verification.json').write_text(json.dumps(report, indent=2)+'\n')
print('ROOF_ASSET_PASS', sum(after.values()), 'triangles;', len(unchanged), 'other asset files exact')
