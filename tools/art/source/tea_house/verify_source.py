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
report={'checks':CHECKS,'passed':all(c['passed'] for c in CHECKS)}
(ROOT/'output/tea-216/source-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
if not report['passed']:sys.exit(1)
