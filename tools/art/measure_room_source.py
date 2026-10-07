"""Blender-side measured scale and metre-based cloth checks for Zhao Yun rooms."""
from pathlib import Path
import json,sys,bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];slug=sys.argv[sys.argv.index('--')+1];source=ROOT/'tools/art/source'/slug;doc=ROOT/'docs/design'/(slug+'-2026-10-07')
spec=json.loads((source/'scale-source.json').read_text());layout=json.loads((ROOT/'assets/rooms'/slug/'layout.json').read_text());bpy.ops.wm.open_mainfile(filepath=str(source/(slug+'.blend')));bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();results={}
for key,query in spec.items():
 declared=layout['bench']['scale'][key]
 if not declared.get('applicable',True):
  assert declared.get('reason');results[key]={'applicable':False,'reason':declared['reason']};continue
 objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith(query['name']) and o.parent and o.parent.name==query['kit']]
 assert objects,(key,query)
 points=[o.matrix_world@Vector(q) for o in objects for q in o.evaluated_get(deps).bound_box];lo=min(q.z for q in points);hi=max(q.z for q in points);height=hi-lo if query.get('clear_height') else hi-query.get('floor',.082)
 results[key]={'source_objects':[o.name for o in objects],'world_min_y':lo,'world_max_y':hi,'measured_height':height,'declared_height':declared['height'],'passed':abs(height-declared['height'])<.015};assert results[key]['passed'],results[key]
(doc/'source-scale.json').write_text(json.dumps(results,indent=2)+'\n')
checks=[]
for obj in bpy.context.scene.objects:
 if obj.type!='MESH' or 'MetricClothUV' not in obj.data.uv_layers:continue
 uv=obj.data.uv_layers['MetricClothUV'];ratios=[]
 for face in obj.data.polygons:
  ids=list(face.loop_indices)
  for i,a in enumerate(ids):
   b=ids[(i+1)%len(ids)];duv=(uv.data[a].uv-uv.data[b].uv).length
   if duv>.0001:
    pa=obj.data.vertices[obj.data.loops[a].vertex_index].co;pb=obj.data.vertices[obj.data.loops[b].vertex_index].co;ratios.append((pa-pb).length/duv)
 checks.append({'object':obj.name,'uv_layer':'MetricClothUV','edges':len(ratios),'minimum':min(ratios),'maximum':max(ratios),'passed':min(ratios)>.9 and max(ratios)<1.1})
assert all(c['passed'] for c in checks)
(doc/'cloth-uv-verification.json').write_text(json.dumps({'checks':checks,'passed':all(c['passed'] for c in checks),'scope':'Authored folded cloth only; no metric UV claim for props without this layer.'},indent=2)+'\n')
print('SOURCE_SCALE_AND_CLOTH_VERIFIED',slug,flush=True)
