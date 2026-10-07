"""Measure evaluated source mesh worktop/seat heights against Basic Room."""
from pathlib import Path
import bpy,json,sys
ROOT=Path(__file__).resolve().parents[4]
slug=sys.argv[sys.argv.index('--')+1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/art/source'/slug/(slug+'.blend')))
if slug=='tavern':
 specs=[('long_bar','thick oak top',1.1525),('bar_return','thick oak top',1.1525),('round_table','timber tabletop',1.135),('square_table','tabletop',1.135),('bar_stool','seat',.685),('dining_stool','seat',.685),('square_dining_stool','seat',.685),('backed_dining_stool','seat',.685)]
else:
 specs=[('anvil_workbench','top plank',1.135),('back_tool_bench','top plank',1.135),('forge_stool','seat',.685)]
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();rows=[]
for name,word,baseline in specs:
 root=bpy.data.objects[name];collection=bpy.data.collections['KIT_'+name];objects=[o for o in collection.objects if o.type=='MESH' and word in o.name.lower()]
 assert objects,(name,word)
 vals=[]
 for o in objects:
  evaluated=o.evaluated_get(deps);mesh=evaluated.to_mesh();inv=root.matrix_world.inverted()
  vals += [(inv @ o.matrix_world @ vertex.co).z for vertex in mesh.vertices];evaluated.to_mesh_clear()
 top=max(vals);delta=abs(top/baseline-1);rows.append({'asset':name,'object_names':[o.name for o in objects],'floor_pivot_to_top_m':top,'baseline_m':baseline,'relative_difference':delta,'passed':delta<=.15})
result={'method':'Evaluated editable Blender mesh vertices transformed into the module floor-pivot frame; top of named seat/worktop parts; no manifest height values used.','checks':rows,'passed':all(r['passed'] for r in rows)}
(ROOT/'docs/design'/(slug+'-2026-10-07')/'dimensions-r2.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));assert result['passed']
