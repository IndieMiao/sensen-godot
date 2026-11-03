"""Read-only audit of named editable parts and authored support contacts."""
from pathlib import Path
import json
import bpy

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
bpy.ops.wm.open_mainfile(filepath=str(SRC/'classroom_props.blend'))
graph=bpy.context.evaluated_depsgraph_get()
checks=[]
def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
def bounds(collection,name):
    obj=next(o for o in collection.objects if o.name.startswith(name))
    root=next(o for o in collection.objects if o.type=='EMPTY')
    evaluated=obj.evaluated_get(graph);mesh=evaluated.to_mesh()
    points=[root.matrix_world.inverted()@obj.matrix_world@v.co for v in mesh.vertices]
    evaluated.to_mesh_clear()
    return [[min(v[i] for v in points) for i in range(3)],[max(v[i] for v in points) for i in range(3)]]
collections=[c for c in bpy.data.collections if c.name.startswith('KIT_')]
check(len(collections)==7,'Seven editable module collections')
for c in collections:
    meshes=[o for o in c.objects if o.type=='MESH']
    check(len(meshes)>0 and all(not o.name.startswith(('Cube','Sphere','Cone','Icosphere')) for o in meshes),c.name+': descriptive editable parts')
    check(sum(o.type=='EMPTY' for o in c.objects)==1,c.name+': one local module root')
study=bpy.data.collections['KIT_plaster_study']
base=bounds(study,'Geometric study plinth');solid=bounds(study,'Faceted geometric study')
check(abs(solid[0][2]-base[1][2])<.00001,'Geometric study flat face touches plinth')
desk=bpy.data.collections['KIT_teacher_desk'];top=bounds(desk,'Rounded wood desktop')
check(abs(top[1][2]-1.13425)<.00001,'Editable source desktop at .65H')
check(len(bpy.data.scenes)==1,'Temporary export scene removed from source')
report={'checks':checks,'named_parts':{c.name:len([o for o in c.objects if o.type=='MESH']) for c in collections},
    'passed':all(c['passed'] for c in checks)}
(ROOT/'output/classroom-props-322/source-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('SOURCE_VALIDATION',report['passed'],len(checks))
assert report['passed']
