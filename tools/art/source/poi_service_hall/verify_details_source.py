"""Inspect named editable construction parts in the delivered Blender source."""
from pathlib import Path
import json
import sys
import bpy
import numpy as np

SRC=Path(__file__).resolve().parent
ROOT=SRC.parents[3]
CHECKS=[]


def check(ok,label,**measured):CHECKS.append({'check':label,'passed':bool(ok),**measured})


def bounds(obj,root):
    bpy.context.view_layer.update()
    evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data=evaluated.to_mesh()
    points=np.array([tuple(root.matrix_world.inverted() @ obj.matrix_world @ vertex.co) for vertex in data.vertices])
    evaluated.to_mesh_clear()
    return points.min(0),points.max(0)


bpy.ops.wm.open_mainfile(filepath=str(SRC/'service_hall_details.blend'))
for name in ['display_niche_1','display_niche_2']:
    collection=bpy.data.collections['KIT_'+name];root=bpy.data.objects[name]
    shelf=next(o for o in collection.objects if o.name.startswith('Exhibition shelf'))
    low,high=bounds(shelf,root)
    check(abs(high[2]-.75)<1e-5,name+': actual display shelf top .75m',top_m=float(high[2]))
    expected=['Tall ivory vase','Faceted pale gemstone'] if name.endswith('1') else ['Small ceramic bowl','Tall geometric display','Small geometric display']
    check(all(any(o.name.startswith(prefix) for o in collection.objects) for prefix in expected),name+': editable distinct display objects')
call=bpy.data.collections['KIT_call_screen']
check(sum(o.name.startswith('Colour dot ') for o in call.objects)==3,'Call screen has exactly three coloured dots')
notice=bpy.data.collections['KIT_notice_board']
check(sum(o.name.startswith('Blank paper ') for o in notice.objects)==4,'Notice board has exactly four blank papers')
check(not any(o.type=='FONT' for o in bpy.data.objects),'No text or number objects in detailed kit')
sculpture=bpy.data.collections['KIT_sculpture_body']
check(all(any(o.name.startswith(prefix) for o in sculpture.objects) for prefix in ['Open curling spiral','Tapered rising ribbon','Central pearl']),
      'Sculpture retains separate editable open ribbons and pearl')
data={'passed':all(c['passed'] for c in CHECKS),'checks':CHECKS}
path=ROOT/'output/poi-service-hall-321/details-source-validation.json'
path.write_text(json.dumps(data,indent=2)+'\n');print(json.dumps(data))
if not data['passed']:sys.exit(1)
