from pathlib import Path
import json,hashlib,sys,shutil
from PIL import Image
import numpy as np
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent;KIT=ROOT/'assets/rooms/_shared/church_kit';ORIGINAL=ROOT/'assets/rooms/poi_church'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
m=json.loads((KIT/'kit_manifest.json').read_text());original=json.loads((SRC/'original-files.json').read_text())
for name in json.loads((SRC/'copied-assets.json').read_text())['assets']:
 path=KIT/(name+'.glb');d,b=load_glb(path);p=d['meshes'][0]['primitives'][0];v=np.array(accessor(d,b,p['attributes']['POSITION']))
 m['assets'][name]={'file':path.name,'triangles':len(accessor(d,b,p['indices']))//3,'surfaces':1,'bounds':[v.min(0).tolist(),v.max(0).tolist()],'dimensions_m':np.ptp(v,axis=0).tolist(),'material':'atlas','source':'tools/art/source/church_kit/'+name+'.blend','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'reuse_from':'assets/rooms/poi_church/'+path.name,'geometry':'Original BIN and all JSON fields unchanged except shared atlas URI','mount_plane':'original local pivot; see dimensions/attachments'}
m['assets']['wood_pew']['seat_height_m']=.715;m['assets']['iron_chandelier']['ceiling_hook']=[0,1.8,0];m['assets']['altar_table']['tabletop_height_m']=1.12
# Both palettes use the same semantic cell indices. Lead is fixed, calm and dark.
palettes={'classic':['719ABF','517995','D68F70','E7BD68','F2DC9F','5D4C38','EBD8BC','FFFFFF'],'meadow':['8AAFA2','5C827B','B790A6','C4B36F','E8E1BD','5D4C38','EBD8BC','FFFFFF']}
for name,colors in palettes.items():
 im=Image.new('RGB',(8,1));im.putdata([tuple(bytes.fromhex(h)) for h in colors]);im.save(KIT/('glass_palette_'+name+'.png'))
m['palettes']={'slots':m['glass_palette_slots']+['reserved_stone','reserved_white'],'presets':palettes,'parameter':'palette_texture on glass_palette_*.tres','scope':'Only pointed_glass / rose_glass; opaque stone/wood/props unchanged'}
m['source_preservation']={'base_commit':original['base'],'original_directory':'assets/rooms/poi_church','expected_file_count':len(original['sha256']),'hash_record':'tools/art/source/church_kit/original-files.json'}
m['unique_triangles']=sum(a['triangles'] for a in m['assets'].values());m['unique_surfaces']=sum(a['surfaces'] for a in m['assets'].values())
for name,row in m['assets'].items():
 d=SRC/'modules'/name;d.mkdir(parents=True,exist_ok=True);provenance={'author':m['author'],'virtual_user_id':m['virtual_user_id'],'source_commit':original['base'],'module':name,'source':row.get('reuse_from',row.get('source_collection','Grace Cathedral palette and pointed-window proportions')),'changes':'Original geometry BIN and JSON preserved; only image URI points to shared poi_church atlas; independent UID' if row['material']=='atlas' else 'Palette-index UV from named glass groups; same source geometry/local pivot' if row['material']=='glass' else 'Modular geometry or extracted stone frame, metre dimensions; standalone vertex-colour material','editable_source':row['source'],'script':'tools/art/source/church_kit/build.py' if row['material']!='atlas' else 'tools/art/source/church_kit/prepare_assets.py'}
 (d/'reuse_provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n');row['provenance']=str((d/'reuse_provenance.json').relative_to(ROOT))
(KIT/'kit_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n');print('KIT',len(m['assets']),m['unique_triangles'],m['unique_surfaces'])
