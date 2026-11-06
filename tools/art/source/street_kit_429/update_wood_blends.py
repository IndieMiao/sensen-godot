"""Sync the two editable sources; run Blender under shared flock."""
from pathlib import Path
import bpy
SRC=Path(__file__).resolve().parent
MAPPING={'BB8B52':'A3815D','D0A56C':'B89972','9A7046':'795F47'}
def linear(h):return tuple(x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in [v/255 for v in bytes.fromhex(h)])
for name in ['bench_wood','umbrella_table']:
 path=SRC/(name+'.blend');bpy.ops.wm.open_mainfile(filepath=str(path));bpy.context.preferences.filepaths.save_version=0
 materials={mat for obj in bpy.context.scene.objects if obj.type=='MESH' for mat in obj.data.materials}
 for mat in materials:
  old=next((h for h in MAPPING if max(abs(x-y) for x,y in zip(mat.diffuse_color[:3],linear(h)))<.0001),None)
  if old is None:continue
  color=(*linear(MAPPING[old]),mat.diffuse_color[3]);mat.diffuse_color=color
  if mat.use_nodes:mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=color
 bpy.ops.wm.save_as_mainfile(filepath=str(path));print('UPDATED_SOURCE_COLOURS',name,flush=True)
