from pathlib import Path
import json,bpy,math
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'output/zhaoyun-175-r21-2026-10-08';layout=json.loads((ROOT/'assets/rooms/bakery/layout.json').read_text());bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/art/source/bakery/bakery.blend'));bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
inventory=layout['pastry_display'];assert inventory['placed_count']>=20 and inventory['prototype_count']==11
sequences=inventory['layers_bottom_to_top'];assert len({tuple(row) for row in sequences})==3
assert all(any(k in name for k in ('croissant','loaf','baguette')) for name in sequences[0]);assert all(any(k in name for k in ('cake','tart')) for name in sequences[-1])
old_bars=[o.name for o in bpy.context.scene.objects if any(x in o.name.lower() for x in ('flour slash','flour score','diagonal score'))];assert not old_bars,old_bars
scored=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.get('bread_score')];assert scored
crumb_faces=[sum(p.material_index==1 for p in o.data.polygons) for o in scored];assert all(n>0 for n in crumb_faces)
def v(q):return Vector((q[0],-q[2],q[1]))
cam=layout['camera'];eye=v(cam['position']);target=v(cam['target']);f=(target-eye).normalized();right=f.cross(Vector((0,0,1))).normalized();up=right.cross(f).normalized()
def rect(objects):
 pts=[o.matrix_world@Vector(c) for o in objects for c in o.evaluated_get(deps).bound_box]
 xy=[(720+(p-target).dot(right)*1440/cam['size'],540-(p-target).dot(up)*1440/cam['size']) for p in pts]
 return [min(p[0] for p in xy),min(p[1] for p in xy),max(p[0] for p in xy),max(p[1] for p in xy)]
plant=rect([o for o in bpy.data.collections['SHARED_front_peace_lily'].objects if o.type=='MESH'])
case=rect([o for o in bpy.data.collections['KIT_display_frame'].objects if o.type=='MESH'])
separate=plant[0]>case[2] or plant[2]<case[0] or plant[1]>case[3] or plant[3]<case[1];assert separate,(plant,case)
result={'passed':True,'inventory':inventory,'scored_source_objects_including_prototypes':len(scored),'minimum_cut_crumb_faces':min(crumb_faces),'legacy_raised_white_score_objects':old_bars,'plant_projected_bounds':plant,'case_projected_bounds':case,'plant_does_not_overlap_display_bounds':separate,'scope':'Evaluated Blender source, declared accepted camera, source inventory and actual recessed faces. Godot visual/route verification remains pending due unavailable desktop.'}
(OUT/'source-audit.json').write_text(json.dumps(result,indent=2)+'\n');print('SOURCE_AUDIT_PASS',len(scored),plant,case)
