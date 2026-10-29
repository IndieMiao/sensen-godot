"""Blender source/export parity audit. Run with Blender --background --python."""
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/art'))
from verify_chef_sign import load_glb, accessor

source = ROOT/'tools/art/source/sprinkler_244/sprinkler_244.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
bpy.context.view_layer.update()
report = {'checks': [], 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'parts': {}}


def check(ok, label):
    report['checks'].append({'passed': bool(ok), 'check': label})
    if not ok: print('FAIL', label)


doc, blob = load_glb(ROOT/'assets/farm/art/sprinkler.glb')
for name in ['base', 'head']:
    collection = bpy.data.collections['Sprinkler_'+name]
    points = []
    for obj in collection.objects:
        if obj.type != 'MESH': continue
        for vertex in obj.data.vertices:
            p = obj.matrix_world@vertex.co
            points.append(Vector((p.x,p.z,-p.y)))
    node = next(n for n in doc['nodes'] if n['name']==name)
    prim = doc['meshes'][node['mesh']]['primitives'][0]
    offset = Vector(node.get('translation',[0,0,0]))
    exported = [Vector(v)+offset for v in accessor(doc,blob,prim['attributes']['POSITION'])]
    maximum = 0
    for a,b in [(points,exported),(exported,points)]:
        tree = KDTree(len(b))
        for i,p in enumerate(b): tree.insert(p,i)
        tree.balance()
        maximum = max(maximum,max(tree.find(p)[2] for p in a))
    check(maximum < .000001, name+' source/export bidirectional vertex error <1 micrometre')
    root = bpy.data.objects[name]
    check(root.location.length<1e-7 if name=='base' else (root.location-Vector((0,0,.55))).length<1e-7,
          name+' editable pivot matches export')
    report['parts'][name] = {'source_objects': len([o for o in collection.objects if o.type=='MESH']),
                            'maximum_vertex_error_m': maximum}
check((bpy.data.objects['spray_origin'].location-Vector((0,0,.55))).length<1e-7,'editable spray_origin correct')
report['passed'] = all(c['passed'] for c in report['checks'])
(ROOT/'output/sprinkler-244/source-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('SPRINKLER_SOURCE', report['passed'])
if not report['passed']: raise RuntimeError('Source validation failed')
