"""Read-only Blender reopen check: editable parts match the exported budget/bounds."""
from pathlib import Path
import bpy,json
from mathutils import Vector
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
bpy.ops.wm.open_mainfile(filepath=str(SRC/'alcatraz_foam.blend'))
manifest=json.loads((ROOT/'assets/landmarks/alcatraz_island/alc_shore_foam_manifest.json').read_text())
rows=[]
for name,a in manifest['assets'].items():
 col=bpy.data.collections[name];points=[];tri=0
 for o in col.objects:
  assert o.type=='MESH' and o.matrix_world==__import__('mathutils').Matrix.Identity(4)
  assert len(o.data.materials)==1 and o.data.color_attributes.get('Color')
  assert not o.modifiers
  o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles)
  points.extend(Vector((p.co.x,p.co.z,-p.co.y)) for p in o.data.vertices)
 bounds=[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
 assert tri==a['triangles']
 assert all(abs(bounds[k][i]-a['bounds'][k][i])<.0001 for k in range(2) for i in range(3))
 rows.append({'asset':name,'editable_parts':[o.name for o in col.objects],'triangles':tri,'bounds_match':True})
out=ROOT/'docs/design/alcatraz-foam-424/source-validation.json'
out.write_text(json.dumps({'passed':True,'blender':bpy.app.version_string,'assets':rows},indent=2)+'\n')
print('ALC_FOAM_SOURCE_PASS',len(rows))
