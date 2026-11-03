"""Read-only audit of editable collections, the glass separation and contact planes."""
from pathlib import Path
import json
import bpy

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
bpy.ops.wm.open_mainfile(filepath=str(SRC/'culture_props.blend'));graph=bpy.context.evaluated_depsgraph_get()
checks=[]
def check(ok,label):checks.append({'check':label,'passed':bool(ok)})
collections=[c for c in bpy.data.collections if c.name.startswith('KIT_')]
check(len(collections)==8,'8 export groups with named editable components')
for c in collections:
    objects=[o for o in c.objects if o.type=='MESH']
    check(bool(objects) and all(not o.name.startswith(('Cube','Sphere','Cone','Icosphere')) for o in objects),c.name+': descriptive part names')
    check(sum(o.type=='EMPTY' for o in c.objects)==1,c.name+': one local module root')
case=bpy.data.collections['KIT_display_cabinet'];panes=[o for o in case.objects if o.get('surface_role')=='glass']
check(len(panes)==5,'Five independently editable glass panels')
check(all(abs(o.data.materials[0].diffuse_color[3]-.16)<.001 for o in panes),'Source glass transparency visible in Blender')
for name,prefix,wanted in [('display_cabinet','Ivory display bed',1.0),('exhibit_plinth','Ivory exhibit surface',1.10)]:
    c=bpy.data.collections['KIT_'+name];root=next(o for o in c.objects if o.type=='EMPTY');obj=next(o for o in c.objects if o.name.startswith(prefix))
    evaluated=obj.evaluated_get(graph);mesh=evaluated.to_mesh()
    top=max((root.matrix_world.inverted()@obj.matrix_world@v.co).z for v in mesh.vertices);evaluated.to_mesh_clear()
    check(abs(top-wanted)<1e-5,name+': source support height')
check(len(bpy.data.scenes)==1,'Temporary export scene removed')
report={'checks':checks,'named_parts':{c.name:sum(o.type=='MESH' for o in c.objects) for c in collections},'passed':all(c['passed'] for c in checks)}
(ROOT/'output/culture-props-323/source-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('SOURCE_VALIDATION',report['passed'],len(checks));assert report['passed']
