"""Read-only Blender source measurement, including bevel modifier evaluation."""
from pathlib import Path
import json
import bpy
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/reed-clay-416'
manifest=json.loads((ROOT/'assets/farm/art/manifest.json').read_text());checks=[];assets={}
def check(ok,label):checks.append({'check':label,'passed':bool(ok)})
for name in ['reed_bank','clay_pit']:
    bpy.ops.wm.open_mainfile(filepath=str(SRC/(name+'.blend')))
    root=bpy.data.objects[name+' / bottom-centre pivot'];spec=manifest['assets'][name]
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH'];points=[];triangles=0
    check(root.location.length<1e-8 and tuple(root.scale)==(1.,1.,1.),name+': unit bottom-centre pivot')
    check({o.name for o in objects}==set(spec['source_parts_triangles']),name+': all construction parts independently named')
    depsgraph=bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        mesh=bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph));mesh.calc_loop_triangles();triangles+=len(mesh.loop_triangles)
        check(obj.parent==root and len(mesh.loop_triangles)==spec['source_parts_triangles'][obj.name],name+': '+obj.name)
        for vertex in mesh.vertices:
            p=obj.matrix_world@vertex.co;points.append((p.x,p.z,-p.y))
        bpy.data.meshes.remove(mesh)
    lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
    check(triangles==spec['triangles'],name+': source triangle count matches GLB')
    check(max(abs(lo[i]-spec['bounds'][0][i]) for i in range(3))<1e-6 and max(abs(hi[i]-spec['bounds'][1][i]) for i in range(3))<1e-6,name+': source bounds match GLB')
    assets[name]={'parts':len(objects),'triangles':triangles,'bounds':[lo,hi]}
report={'checks':checks,'assets':assets,'passed':all(c['passed'] for c in checks)}
(OUT/'source-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('REED_CLAY_SOURCE',report['passed'],len(checks));assert report['passed']
