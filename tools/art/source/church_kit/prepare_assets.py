"""Copy meshes, share the shipped atlas; never write to poi_church."""
from pathlib import Path
import json,hashlib,shutil,subprocess,struct
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent;ORIGINAL=ROOT/'assets/rooms/poi_church';KIT=ROOT/'assets/rooms/_shared/church_kit'
copy_names=['wood_pew','altar_table','sanctuary_steps','iron_chandelier','pipe_organ','flower_pedestal','grass_surround']
base=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip()
record=SRC/'original-files.json'
if not record.exists():record.write_text(json.dumps({'base':base,'directory':'assets/rooms/poi_church','sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(ORIGINAL.rglob('*')) if p.is_file()}},ensure_ascii=False,indent=2)+'\n')
for name in copy_names:
 raw=(ORIGINAL/(name+'.glb')).read_bytes();length,kind=struct.unpack_from('<II',raw,12);assert kind==0x4e4f534a
 doc=json.loads(raw[20:20+length]);assert doc['images']==[{'uri':'room_albedo_ao.png'}]
 doc['images'][0]['uri']='../../poi_church/room_albedo_ao.png'
 payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4)
 tail=raw[20+length:]  # Preserve every geometry/UV/colour byte and BIN chunk.
 (KIT/(name+'.glb')).write_bytes(struct.pack('<III',0x46546c67,2,20+len(payload)+len(tail))+struct.pack('<II',len(payload),kind)+payload+tail)
for name in ['room_albedo_ao.png','room_albedo_ao.png.import']:
 duplicate=KIT/name
 if duplicate.exists():duplicate.unlink()
(SRC/'copied-assets.json').write_text(json.dumps({'assets':copy_names,'source':'assets/rooms/poi_church','atlas':'res://assets/rooms/poi_church/room_albedo_ao.png; shared dependency, no duplicate','glb_changes':'Only JSON images[0].uri; complete BIN chunk and all other JSON fields preserved'},indent=2)+'\n')
print('COPIED',copy_names)
