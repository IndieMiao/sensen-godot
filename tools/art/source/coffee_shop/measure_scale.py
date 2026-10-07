"""Measure R1 source geometry, not the movement capsule. Run with Blender."""
from pathlib import Path
import bpy,json
from mathutils import Vector
root=Path(__file__).resolve().parents[4]
bpy.ops.wm.open_mainfile(filepath=str(root/'tools/art/source/coffee_shop/coffee_shop.blend'))
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
def top(name,parent):
 o=next(o for o in bpy.context.scene.objects if o.name.startswith(name) and o.parent and o.parent.name==parent)
 ev=o.evaluated_get(deps)
 return max((ev.matrix_world@Vector(p)).z for p in ev.bound_box)
floor=top('Staggered oak board','floor')
d={'floor_surface_y':floor,'counter':top('Stone worktop','counter')-floor,'chair':top('Ivory upholstered seat','chair')-floor,'table':top('Soft round oak table','table')-floor,'door':2.69,'door_method':'Open limestone arch interior shoulder 1.93 + rise .76; trim excluded'}
(root/'docs/design/coffee_shop-2026-10-07/source-scale.json').write_text(json.dumps(d,indent=2)+'\n');print('SOURCE_SCALE',d)
