"""Blender-side independent check of the named seat surfaces and editable source."""
from pathlib import Path
import json
import bpy

ROOT=Path(__file__).resolve().parents[4]
bpy.ops.wm.open_mainfile(filepath=str(Path(__file__).with_name('poi_city_park.blend')))
bpy.context.view_layer.update()
deps=bpy.context.evaluated_depsgraph_get()
result={'collections':{},'checks':[]}
for name in ['green_bench','white_bench','fountain','entry_gate','rose_arch']:
    collection=bpy.data.collections['KIT_'+name]
    root=bpy.data.objects[name]
    parts=[]
    for obj in collection.objects:
        if obj.type!='MESH':continue
        evaluated=obj.evaluated_get(deps)
        data=bpy.data.meshes.new_from_object(evaluated,depsgraph=deps)
        transform=root.matrix_world.inverted()@obj.matrix_world
        coords=[transform@v.co for v in data.vertices]
        parts.append({'name':obj.name,'bounds_yup':[[min(v.x for v in coords),min(v.z for v in coords),-max(v.y for v in coords)],
                                                  [max(v.x for v in coords),max(v.z for v in coords),-min(v.y for v in coords)]]})
        bpy.data.meshes.remove(data)
    result['collections'][name]=parts
seats=[p['bounds_yup'][1][1] for p in result['collections']['green_bench'] if 'seat plank' in p['name']]
result['checks'].append({'check':'Three actual green bench seat planks have top at .715m','passed':len(seats)==3 and all(abs(y-.715)<.00001 for y in seats),'measured_y_m':seats})
top=max(p['bounds_yup'][1][1] for p in result['collections']['green_bench'])
result['checks'].append({'check':'Actual green bench back top .95m','passed':abs(top-.95)<.00001,'measured_y_m':top})
rays=[obj for obj in bpy.data.collections['KIT_brick_paths'].objects if obj.type=='MESH' and obj.name.startswith('White stone pointed ray')]
tip=max((obj.matrix_basis@vertex.co).xy.length for obj in rays for vertex in obj.data.vertices)
result['checks'].append({'check':'Sixteen short white stone rays within 1.04m grass boundary','passed':len(rays)==16 and tip<=1.00001,'ray_count':len(rays),'tip_radius_m':tip})
plaque=next(p for p in result['collections']['entry_gate'] if 'plaque' in p['name'])
result['checks'].append({'check':'Entry plaque lower edge clears 1.745m character','passed':plaque['bounds_yup'][0][1]>2.0,'clearance_m':plaque['bounds_yup'][0][1]})
result['passed']=all(c['passed'] for c in result['checks'])
output=ROOT/'output/poi-city-park-320/source-validation.json'
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(result,indent=2)+'\n')
print('SOURCE_VALIDATION',result['checks'])
assert result['passed']
