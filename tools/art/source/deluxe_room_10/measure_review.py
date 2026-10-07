"""Check editable source scales and metric duvet UVs."""
from pathlib import Path
import bpy,json
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[4];DOC=ROOT/'docs/design/deluxe_room_10-2026-10-07'
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/art/source/deluxe_room_10/deluxe_room_10.blend'))
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
queries={'door':('green_door','Sage arched door'),'counter':('island','Oak counter'),'chair':('dining_chair','Sage chair seat pad'),'table':('dining_table','Individual tabletop board')}
r={}
for key,(parent,prefix) in queries.items():
 objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith(prefix) and o.parent and o.parent.name==parent]
 assert objects,(key,parent,prefix)
 points=[o.matrix_world@Vector(q) for o in objects for q in o.evaluated_get(deps).bound_box];lo=min(p.z for p in points);hi=max(p.z for p in points)
 r[key]={'source_objects':[o.name for o in objects],'height_above_floor':hi-.082,'clear_height':hi-lo if key=='door' else None,'world_min_y':lo,'world_max_y':hi}
(DOC/'source-scale.json').write_text(json.dumps(r,indent=2)+'\n')
checks=[]
for o in bpy.context.scene.objects:
 if o.type!='MESH' or 'MetricClothUV' not in o.data.uv_layers:continue
 uv=o.data.uv_layers['MetricClothUV'];ratios=[]
 for poly in o.data.polygons:
  ids=list(poly.loop_indices)
  for i,a in enumerate(ids):
   b=ids[(i+1)%len(ids)];pa=o.data.vertices[o.data.loops[a].vertex_index].co;pb=o.data.vertices[o.data.loops[b].vertex_index].co;d=(uv.data[a].uv-uv.data[b].uv).length
   if d>.0001:ratios.append((pa-pb).length/d)
 checks.append({'object':o.name,'uv_layer':'MetricClothUV','minimum':min(ratios),'maximum':max(ratios),'edges':len(ratios),'passed':min(ratios)>.9 and max(ratios)<1.1})
(DOC/'cloth-uv-verification.json').write_text(json.dumps({'checks':checks,'passed':all(c['passed'] for c in checks)},indent=2)+'\n');assert all(c['passed'] for c in checks);print(json.dumps(r,indent=2))
