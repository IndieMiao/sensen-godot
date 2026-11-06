"""Compare editable owned mesh/UV data before and after material integration."""
from pathlib import Path
import bpy,hashlib,json
ROOT=Path(__file__).resolve().parents[4]
names=['alc_ground_dock','alc_ground_terraces','alc_ground_summit','dock','alc_museum','ruins']
def fingerprint(path):
    bpy.ops.wm.open_mainfile(filepath=str(path));result={}
    for name in names:
        rows=[]
        for obj in sorted(bpy.data.collections[name].objects,key=lambda o:o.name):
            assert obj.type=='MESH',(name,obj.type)
            mesh=obj.data
            rows.append({'name':obj.name,'matrix':[list(r) for r in obj.matrix_world],
                'vertices':[list(v.co) for v in mesh.vertices],
                'faces':[list(p.vertices) for p in mesh.polygons],
                'uv':{u.name:[list(x.uv) for x in u.data] for u in mesh.uv_layers},
                'materials':[list(m.diffuse_color) for m in mesh.materials],
                'material_indices':[p.material_index for p in mesh.polygons]})
        result[name]=hashlib.sha256(json.dumps(rows,sort_keys=True).encode()).hexdigest()
    return result
a=fingerprint(ROOT/'output/alcatraz-424/v9/baseline-source.blend')
b=fingerprint(ROOT/'tools/art/source/alcatraz_island/alcatraz_blockout.blend')
assert a==b,(a,b)
(ROOT/'docs/design/alcatraz-blockout-424-2026-11-05/v9/editable-geometry-preservation.json').write_text(json.dumps({'passed':True,'baseline':'b81605af','compared':'editable vertex/face/UV/transform/material assignments','identical_modules':a},indent=2)+'\n')
print('EDITABLE_PRESERVATION pass: 6 owned collections')
