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
report = {'checks': [], 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'parts': {}, 'measurements': {}}


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
    check(root.location.length<1e-7 if name=='base' else (root.location-Vector((0,0,.42))).length<1e-7,
          name+' editable pivot matches export')
    report['parts'][name] = {'source_objects': len([o for o in collection.objects if o.type=='MESH']),
                            'maximum_vertex_error_m': maximum}
check((bpy.data.objects['spray_origin'].location-Vector((0,0,.42))).length<1e-7,'editable spray_origin correct')
for label in ['Round edged stone mounting pad', 'Stout sage green riser',
              'Rounded yellow brass rotating hub', 'Blue water droplet cap']:
    obj = bpy.data.objects[label]
    points = [obj.matrix_world@v.co for v in obj.data.vertices]
    report['measurements'][label] = {
        'diameter_m': 2*max(Vector((p.x,p.y)).length for p in points),
        'bottom_m': min(p.z for p in points), 'top_m': max(p.z for p in points)}
pad = report['measurements']['Round edged stone mounting pad']
hub = report['measurements']['Rounded yellow brass rotating hub']
riser = bpy.data.objects['Stout sage green riser']
for height, diameter in [(.050,.130),(.362,.110)]:
    ring = [riser.matrix_world@v.co for v in riser.data.vertices
            if abs((riser.matrix_world@v.co).z-height)<1e-6]
    measured = 2*max(Vector((p.x,p.y)).length for p in ring)
    report['measurements']['riser_at_'+str(height)+'m'] = {'diameter_m': measured}
    check(abs(measured-diameter)<1e-6,'v1.2 tapered riser diameter at '+str(height))
check(abs(hub['diameter_m']-.14)<1e-6 and abs(hub['top_m']-hub['bottom_m']-.07)<1e-6,
      'v1.1 hub actual diameter 0.14m and height 0.07m')
check(abs(pad['diameter_m']-.25)<1e-6,'v1.1 stone diameter 0.25m')
pad_mesh = bpy.data.objects['Round edged stone mounting pad'].data
check(len({round(v.co.z,6) for v in pad_mesh.vertices})==6 and
      len([v for v in pad_mesh.vertices if abs(v.co.z-.012)<1e-6])==16,
      'v1.1 rounded pad has 16 radial segments and six profile levels')
for side in ['Left','Right']:
    nozzle = bpy.data.objects[side+' round nozzle with painted centre']
    diameter = 2*max(v.co.xy.length for v in nozzle.data.vertices)
    report['measurements'][side+' nozzle'] = {'diameter_m': diameter}
    check(abs(diameter-.052)<1e-6,side+' nozzle actual diameter 0.052m')
check(abs(report['measurements']['Blue water droplet cap']['diameter_m']-.10)<1e-6,
      'v1.1 cap actual diameter 0.10m')
cap=report['measurements']['Blue water droplet cap']
check(abs(cap['top_m']-cap['bottom_m']-.092)<1e-6,'amended v1.2 cap height 0.092m')
cap_object=bpy.data.objects['Blue water droplet cap']
check(len([v for v in cap_object.data.vertices if abs(v.co.z-.489)<1e-6])==10,
      'amended v1.2 cap ten radial segments at upper belly')
report['passed'] = all(c['passed'] for c in report['checks'])
(ROOT/'output/sprinkler-244/source-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('SPRINKLER_SOURCE', report['passed'])
if not report['passed']: raise RuntimeError('Source validation failed')
