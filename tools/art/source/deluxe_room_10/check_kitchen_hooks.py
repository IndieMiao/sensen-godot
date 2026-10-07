"""Measured future-module attachment contract; no kitchen gameplay or model."""
from pathlib import Path
import json,bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[4];SOURCE=ROOT/'tools/art/source/deluxe_room_10';DOC=ROOT/'docs/design/deluxe_room_10-2026-10-07'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'deluxe_room_10.blend'));bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
layout=json.loads((ROOT/'assets/rooms/deluxe_room_10/layout.json').read_text());checks=[];points=[]
for spec in layout['attachment_points']:
 obj=bpy.data.objects.get(spec['name']);assert obj and obj.type=='EMPTY',spec['name']
 pos=[obj.matrix_world.translation.x,obj.matrix_world.translation.z,-obj.matrix_world.translation.y]
 error=sum((a-b)**2 for a,b in zip(pos,spec['position']))**.5
 up=(obj.matrix_world.to_3x3()@Vector((0,0,1))).normalized();up_dot=up.dot(Vector((0,0,1)))
 points.append(dict(spec,source_position=pos,source_error_m=error,source_up_dot=up_dot));checks.append(error<.0001 and up_dot>.999)
shade=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith('Green enamel shade'))
verts=[shade.matrix_world@Vector(c) for c in shade.evaluated_get(deps).bound_box];bottom=min(v.z for v in verts)
checks.append(bottom>=2.0)
# Identify source geometry that occupies the cleared prep footprint above counter.
prep=next(p for p in points if p['name']=='prep_area');cx,cy,cz=prep['position'];blocked=[]
for obj in bpy.context.scene.objects:
 if obj.type!='MESH' or obj.hide_render or not obj.parent:continue
 if obj.parent.name in ('kitchen_end','kitchen_fittings','kitchen_utensils'):
  verts=[obj.matrix_world@Vector(c) for c in obj.evaluated_get(deps).bound_box]
  low=[min(getattr(v,a) for v in verts) for a in ('x','z','y')];high=[max(getattr(v,a) for v in verts) for a in ('x','z','y')]
  # Blender Y=-Godot Z; test object's solid AABB against usable patch above top.
  if low[0]<cx+.25 and high[0]>cx-.25 and low[2]<-cz+.25 and high[2]>-cz-.25 and high[1]>cy+.035 and low[1]<cy+.5:blocked.append(obj.name)
checks.append(not blocked)
result={'attachment_points':points,'pendant_shade_bottom_y':bottom,'minimum_y':2.0,'avatar_visual_H':1.7455,'shade_above_avatar_m':bottom-1.7455,'prep_usable_width_m':.50,'prep_source_obstructions':blocked,'passed':all(checks),'scope':'Named source empties/up axes and evaluated shade/clear worktop geometry. Marker nodes are independently read back in Godot capture; kitchen behavior and modules belong to213.'}
(DOC/'kitchen-hooks-verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));assert result['passed']
