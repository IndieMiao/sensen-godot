import bpy,json,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[4]
layout=json.loads((root/'assets/landmarks/alcatraz_island/layout.json').read_text())
manifest=json.loads((root/'assets/landmarks/alcatraz_island/manifest.json').read_text())
rows={}
for name in manifest['assets']:
 collection=bpy.data.collections.get(name)
 assert collection is not None and len(collection.objects)>0,name
 rows[name]={'editable_objects':len(collection.objects),'named_meshes':sum(o.type=='MESH' for o in collection.objects)}
for zone in ['DockZone','TerraceZone','SummitZone','FarZone']:
 collection=bpy.data.collections.get(zone)
 assert collection is not None,zone
 actual=sum(o.instance_type=='COLLECTION' for o in collection.objects)
 expected=sum(p['zone']==zone for p in layout['placements'])
 assert actual==expected,(zone,actual,expected)
treads=[o for o in bpy.data.collections['alc_ground_terraces'].objects if o.name.startswith('flight_') and '_riser_' in o.name]
assert len(treads)==60,len(treads)
report={'passed':True,'blender_version':bpy.app.version_string,'editable_modules':rows,'editable_treads':len(treads),'zones':['DockZone','TerraceZone','SummitZone','FarZone'],'blend_sha256':hashlib.sha256((root/'tools/art/source/alcatraz_island/alcatraz_blockout.blend').read_bytes()).hexdigest()}
(root/'docs/design/alcatraz-blockout-424-2026-11-05/v3/source-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('SOURCE_CHECK',len(rows),'modules,',len(treads),'editable treads; passed')
