"""Read-only named-source geometry, reused ground parts and shared-sprout checks."""
from pathlib import Path
import hashlib,json
import bpy
import numpy as np
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/gathered-417'
stats=json.loads((SRC/'asset_stats.json').read_text());checks=[];measured={};templates=[]
def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)
def points(obj):
    deps=bpy.context.evaluated_depsgraph_get();d=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),depsgraph=deps)
    d.calc_loop_triangles();n=len(d.loop_triangles)
    p=[obj.matrix_world@v.co for v in d.vertices];result=np.array([(v.x,v.z,-v.y) for v in p]);bpy.data.meshes.remove(d)
    return result,n
def normalized(p):return sorted(tuple(float(v) for v in row) for row in np.round(p,6))
reuse_check={'reed_bank':['Small dark wet-mud footprint','Small bank pebble 1','Small bank pebble 2'],
    'clay_pit':['Low grassy rim and shallow ochre pit'],'flax_patch':['Soft light-brown soil border'],
    'hardwood_grove':['Independent ringed stump / walnut bark','Stump cut / three visible growth rings']}
reuse_sources={}
for name,names in reuse_check.items():
    source=next(r['source'] for r in stats[name]['reuse_provenance'] if set(names)<=set(r.get('parts',[])))
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/source));bpy.context.view_layer.update()
    reuse_sources[name]={n:normalized(points(bpy.data.objects[n])[0]) for n in names}
for name,spec in stats.items():
    bpy.ops.wm.open_mainfile(filepath=str(SRC/(name+'_gathered.blend')));bpy.context.view_layer.update()
    root=bpy.data.objects[name+'_gathered / resource-point origin']
    objects={o.name:o for o in bpy.context.scene.objects if o.type=='MESH'};all_points=[];tri=0
    check(root.location.length<1e-8 and tuple(root.scale)==(1.,1.,1.),name+': original resource-point origin at zero, scale one')
    check(set(objects)==set(spec['source_parts_triangles']),name+': editable named parts match manifest')
    for part,obj in objects.items():
        p,n=points(obj);all_points.extend(p);tri+=n
        check(obj.parent==root and n==spec['source_parts_triangles'][part],name+': '+part)
    array=np.array(all_points);lo=array.min(axis=0);hi=array.max(axis=0)
    check(tri==spec['triangles'] and np.allclose([lo,hi],spec['bounds'],atol=1e-6),name+': editable source agrees with actual GLB bounds/budget')
    for part,expected in reuse_sources.get(name,{}).items():check(normalized(points(objects[part])[0])==expected,name+': unchanged reused geometry / origin: '+part)
    for sprout in spec['regrowth_sprouts']:
        signature=[];colors=[]
        for part in sprout['parts']:
            p,_=points(objects[part]);signature.extend(p-np.array(sprout['origin']))
            colors.extend(tuple(np.round(m.diffuse_color[:],6)) for m in objects[part].data.materials)
        templates.append((np.array(signature),sorted(set(colors))))
    measured[name]={'parts':len(objects),'triangles':tri,'bounds':[lo.tolist(),hi.tolist()]}
sprout_error=max(float(np.max(abs(t[0]-templates[0][0]))) for t in templates)
check(len(templates)==8 and all(np.allclose(t[0],templates[0][0],atol=1e-6,rtol=0) and t[1]==templates[0][1] for t in templates),
      'All eight sprouts share geometry/scale within 1e-6m float precision and identical colour')
report={'checks':checks,'assets':measured,'shared_sprout_instances':len(templates),'sprout_max_coordinate_error_m':sprout_error,'passed':all(c['passed'] for c in checks)}
(OUT/'source-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('GATHERED_SOURCE',report['passed'],len(checks));assert report['passed']
