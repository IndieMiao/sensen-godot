"""Keep named editable source materials in sync; geometry is never changed."""
from pathlib import Path
import bpy,json
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];M=json.loads((SRC/'colour-map.json').read_text())
def linear(h):return [v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in [i/255 for i in bytes.fromhex(h)]]
for name in M['assets']:
 path=ROOT/'tools/art/source/alcatraz_far_424'/(name+'.blend');bpy.ops.wm.open_mainfile(filepath=str(path));bpy.context.preferences.filepaths.save_version=0
 for mat in bpy.data.materials:
  role=mat.name.split('.')[0]
  if role not in M['changes']:continue
  color=(*linear(M['new_palette'][role]),1);mat.diffuse_color=color
  if mat.use_nodes and mat.node_tree.nodes.get('Principled BSDF'):mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=color
 bpy.ops.wm.save_as_mainfile(filepath=str(path));print('SOURCE_COLOURS',name)
