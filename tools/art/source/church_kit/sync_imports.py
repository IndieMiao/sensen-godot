from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[4];KIT=ROOT/'assets/rooms/_shared/church_kit';P=ROOT/'output/church-kit-427-v11/project/assets/rooms/_shared/church_kit'
for path in P.iterdir():
 if path.name.endswith(('.import','.gd.uid','.gdshader.uid')):
  text=path.read_text();assert re.search('uid://[a-y0-8]+',text),path
  (KIT/path.name).write_bytes(path.read_bytes())
print('Synced new kit UIDs/imports only')
