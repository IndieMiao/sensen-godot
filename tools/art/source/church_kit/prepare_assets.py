"""Self-contained copies; never write to the shipped poi_church directory."""
from pathlib import Path
import json,hashlib,shutil,subprocess
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent;ORIGINAL=ROOT/'assets/rooms/poi_church';KIT=ROOT/'assets/rooms/_shared/church_kit'
copy_names=['wood_pew','altar_table','sanctuary_steps','iron_chandelier','pipe_organ','flower_pedestal','grass_surround']
base=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip()
record=SRC/'original-files.json'
if not record.exists():record.write_text(json.dumps({'base':base,'directory':'assets/rooms/poi_church','sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(ORIGINAL.rglob('*')) if p.is_file()}},ensure_ascii=False,indent=2)+'\n')
for name in copy_names:shutil.copy2(ORIGINAL/(name+'.glb'),KIT/(name+'.glb'))
shutil.copy2(ORIGINAL/'room_albedo_ao.png',KIT/'room_albedo_ao.png')
(SRC/'copied-assets.json').write_text(json.dumps({'assets':copy_names,'source':'assets/rooms/poi_church','atlas':'independent byte-identical room_albedo_ao.png; all GLB texture URIs resolve inside new kit'},indent=2)+'\n')
print('COPIED',copy_names)
