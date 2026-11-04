"""Read-only check of editable parts, real source bounds and palette identity."""
from pathlib import Path
import json
import bpy

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/trap-402'
spec=json.loads((ROOT/'assets/props/fish_trap_marker/manifest.json').read_text())
bpy.ops.wm.open_mainfile(filepath=str(SRC/'fish_trap_marker.blend'))
checks=[]
def check(ok,label):checks.append({'check':label,'passed':bool(ok)})
root=bpy.data.objects['Waterline origin / unit scale']
parts=[o for o in bpy.data.objects if o.type=='MESH'];points=[];triangles=0
check(root.location.length<1e-8 and tuple(root.scale)==(1.,1.,1.),'Editable waterline pivot is zero at unit scale')
check({o.name for o in parts}==set(spec['source_parts_triangles']),'Every exported part has a named editable source object')
check(len(bpy.data.scenes)==1 and not any(o.type=='ARMATURE' for o in bpy.data.objects),'No temporary export scene or armature in saved source')
for obj in parts:
    obj.data.calc_loop_triangles();triangles+=len(obj.data.loop_triangles)
    check(obj.parent==root and len(obj.data.loop_triangles)==spec['source_parts_triangles'][obj.name],obj.name+': named parent and triangle budget')
    for vertex in obj.data.vertices:
        p=obj.matrix_world@vertex.co;points.append((p.x,p.z,-p.y))
lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
check(triangles==500,'Editable source contains 500 triangles')
check(max(abs(lo[i]-spec['bounds'][0][i]) for i in range(3))<1e-6 and max(abs(hi[i]-spec['bounds'][1][i]) for i in range(3))<1e-6,'Editable source bounds match exported GLB')
report={'checks':checks,'parts':len(parts),'triangles':triangles,'bounds':[lo,hi],'passed':all(c['passed'] for c in checks)}
(OUT/'source-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('TRAP_SOURCE_VALIDATION',report['passed'],len(checks));assert report['passed']
