"""Read evaluated source geometry; run in Blender after rebuilding Standard Room."""
from pathlib import Path
import bpy,json
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[4]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/art/source/standard_room_5/standard_room_5.blend'))
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
queries={'door':'Sage arched door','counter':'Oak countertop','chair':'Sage chair seat pad','table':'Individual tabletop board','range':'Burner grate'}
results={}
for key,prefix in queries.items():
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith(prefix)]
    points=[o.matrix_world@Vector(corner) for o in objects for corner in o.evaluated_get(deps).bound_box]
    low=min(v.z for v in points);high=max(v.z for v in points)
    results[key]={'source_objects':[o.name for o in objects],'world_min_y':low,'world_max_y':high,
                  'height_above_floor':high-.082,'clear_height':high-low if key=='door' else None}
out=ROOT/'docs/design/standard_room_5-review1-2026-10-07/source-scale.json'
out.write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
