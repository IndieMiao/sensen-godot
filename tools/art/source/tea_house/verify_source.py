"""Measure named contact surfaces from the actual editable Blender source."""
from pathlib import Path
import json
import sys
import bpy
import numpy as np

ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(SRC/'tea_house.blend'))
bpy.context.view_layer.update()
CHECKS=[]


def measure(module,prefix):
    collection=bpy.data.collections['KIT_'+module];root=bpy.data.objects[module]
    objects=[o for o in collection.objects if o.name.startswith(prefix)]
    assert len(objects)==1,(module,prefix,[o.name for o in objects])
    obj=objects[0];evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());data=evaluated.to_mesh()
    points=np.array([tuple(root.matrix_world.inverted() @ obj.matrix_world @ vertex.co) for vertex in data.vertices])
    evaluated.to_mesh_clear();return points.min(0),points.max(0)


def check(ok,label,measurement):CHECKS.append({'check':label,'passed':bool(ok),'measured':measurement})


for module,prefix,height in [('counter','Honey counter top',1.15),('window_bench','Window bench seat plank',.715),
        ('round_stool_sage','Soft upholstered seat',.715),('round_stool_linen','Soft upholstered seat',.715),
        ('tea_table_1','Rounded honey table edge',1.0),('tea_table_2','Rounded honey table edge',1.0),
        ('tea_table_3','Rounded honey table edge',1.0),('decorative_door','Closed door backing',2.33)]:
    low,high=measure(module,prefix)
    check(abs(high[2]-height)<1e-5,module+': actual named contact height',float(high[2]))
    if module.startswith('tea_table'):
        size=high-low;check(abs(size[0]-.9)<1e-5 and abs(size[1]-.9)<1e-5,module+': actual tabletop diameter .90m',size.tolist())
check(not any(obj.type=='FONT' for obj in bpy.data.objects),'No baked name lettering',0)
def world_bounds(objects):
    points=[]
    for obj in objects:
        evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());data=evaluated.to_mesh()
        for vertex in data.vertices:
            value=obj.matrix_world @ vertex.co;points.append((value.x,value.z,-value.y))
        evaluated.to_mesh_clear()
    points=np.array(points);return points.min(0),points.max(0)

corner=[o for o in bpy.data.collections['KIT_left_wall'].objects if o.name.startswith('Rounded timber post')]
corner=min(corner,key=lambda o:world_bounds([o])[0][2])
posts=[o for o in bpy.data.collections['KIT_back_wall'].objects if o.name.startswith('Slim structural post')]
first=min(posts,key=lambda o:world_bounds([o])[0][0])
beam=next(o for o in bpy.data.collections['KIT_back_wall'].objects if o.name.startswith('Pale upper timber beam'))
left=world_bounds([corner])[1][0];right=world_bounds([first])[0][0];bottom=world_bounds([beam])[0][1]
lo,hi=world_bounds([o for o in bpy.data.collections['KIT_name_sign'].objects if o.type=='MESH'])
clearances={'wall_bay_width_m':float(right-left),'left_m':float(lo[0]-left),'right_m':float(right-hi[0]),
            'beam_gap_m':float(bottom-hi[1]),'sign_world_bounds':[lo.tolist(),hi.tolist()]}
check(lo[0]>left and hi[0]<right and hi[1]<bottom,'Actual sign fits measured rear-left wall bay below beam',clearances)
check(abs((lo[0]+hi[0])/2-(left+right)/2)<.0001,'Actual sign centred between corner timber and first post',float((lo[0]+hi[0])/2))
report={'checks':CHECKS,'passed':all(c['passed'] for c in CHECKS)}
(ROOT/'output/tea-216/source-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
if not report['passed']:sys.exit(1)
