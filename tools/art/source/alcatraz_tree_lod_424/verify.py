"""Independent exported geometry and current Godot-render evidence audit."""
from pathlib import Path
import hashlib, json, math, re, subprocess, sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'tools/art'))
from verify_chef_sign import load_glb, accessor, cross, sub

KIT = ROOT / 'assets/landmarks/alcatraz_island'
QA = ROOT / 'output/alcatraz-tree-lod-424'
stats = json.loads((KIT / 'tree_lod_manifest.json').read_text())
report = {'author': '赵云', 'checks': [], 'assets': {}}

def check(ok, label):
    report['checks'].append({'check': label, 'passed': bool(ok)})
    if not ok:
        print('FAIL', label)

def dot(a, b):
    return sum(x*y for x, y in zip(a, b))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

for name, entry in stats['assets'].items():
    path = KIT / (name + '.glb')
    doc, binary = load_glb(path)
    check(len(doc.get('meshes', [])) == 1, name + ': one mesh')
    check(len(doc['meshes'][0]['primitives']) == 1, name + ': one surface')
    check(doc['meshes'][0]['name'] == name + '_mobile', name + ': mobile mesh name')
    check(not any(doc.get(k) for k in ['skins', 'animations', 'textures', 'images']), name + ': no skeleton, animation or texture')
    check(len(doc['nodes']) == 1 and doc['nodes'][0] == {'mesh': 0, 'name': name}, name + ': identity root, no pivot translation or scale')
    check(len(doc['materials']) == 1, name + ': one material')
    pbr = doc['materials'][0]['pbrMetallicRoughness']
    check(pbr['metallicFactor'] == 0 and abs(pbr['roughnessFactor']-.9) < 1e-6, name + ': matte material')
    primitive = doc['meshes'][0]['primitives'][0]
    check(set(primitive['attributes']) == {'POSITION', 'NORMAL', 'COLOR_0'}, name + ': vertex colour contract')
    pos = accessor(doc, binary, primitive['attributes']['POSITION'])
    normals = accessor(doc, binary, primitive['attributes']['NORMAL'])
    colors = accessor(doc, binary, primitive['attributes']['COLOR_0'])
    ids = [i[0] for i in accessor(doc, binary, primitive['indices'])]
    triangles = len(ids)//3
    check(triangles <= 120 and triangles == entry['triangles'], name + ': measured triangle budget')
    check(all(math.isfinite(x) for a in [pos, normals, colors] for row in a for x in row), name + ': finite attributes')
    check(all(abs(dot(n, n)-1) < 1e-4 for n in normals), name + ': unit normals')
    check(all(all(0 <= x <= 1 for x in c) and (len(c) == 3 or c[3] == 1) for c in colors), name + ': valid opaque vertex colours')
    bounds = [[min(p[k] for p in pos) for k in range(3)], [max(p[k] for p in pos) for k in range(3)]]
    check(all(abs(bounds[j][k]-entry['near_bounds'][j][k]) < 1e-5 for j in range(2) for k in range(3)), name + ': exact near/far bounds')
    check(abs(bounds[0][1]) < 1e-6, name + ': bottom on Y=0')
    min_dot = 1
    degenerate = 0
    backwards = 0
    for offset in range(0, len(ids), 3):
        a, b, c = ids[offset:offset+3]
        face = cross(sub(pos[b], pos[a]), sub(pos[c], pos[a]))
        length = math.sqrt(dot(face, face))
        if length < 1e-9:
            degenerate += 1
            continue
        n = [sum(normals[i][k] for i in [a,b,c])/3 for k in range(3)]
        agreement = dot(face, n)/length
        min_dot = min(min_dot, agreement)
        backwards += agreement <= 0
    check(degenerate == 0 and backwards == 0, name + ': no degenerate or reversed shading faces')
    check(sha(path) == entry['sha256'], name + ': current manifest hash')
    for suffix in ['.glb', '.glb.import']:
        near = KIT / (entry['near'] + suffix)
        committed = subprocess.check_output(['git','show','HEAD:' + near.relative_to(ROOT).as_posix()], cwd=ROOT)
        check(near.read_bytes() == committed, name + ': approved near ' + suffix + ' unchanged')
    settings = (KIT/(name+'.glb.import')).read_text()
    uid = re.search(r'^uid="(uid://[a-z0-9]+)"$', settings, re.M)
    check(uid is not None, name + ': generated Godot UID')
    for setting in ['gltf/texture_map_mode=1','meshes/light_baking=1','meshes/generate_lods=false']:
        check(setting in settings.splitlines(), name + ': ' + setting)
    report['assets'][name] = dict(triangles=triangles, surfaces=1, bounds=bounds, sha256=sha(path), near_sha256=sha(KIT/(entry['near']+'.glb')), uid=uid.group(1) if uid else None, degenerate_faces=degenerate, reversed_faces=backwards, minimum_face_normal_agreement=min_dot)

render = json.loads((QA/'render-validation.json').read_text())
check(render['passed'] and all(c['passed'] for c in render['checks']), 'native Godot visibility_range checks passed')
for name, entry in report['assets'].items():
    check(render['assets'][name]['sha256'] == entry['sha256'], name + ': current GLB actually rendered')
report['native_render_checks'] = len(render['checks'])
report['passed'] = all(c['passed'] for c in report['checks'])
(QA/'geometry-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print('TREE_LOD_GEOMETRY', report['passed'], len(report['checks']), 'checks')
raise SystemExit(0 if report['passed'] else 1)
