from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[4];REL=Path('assets/landmarks/_shared/dock_props')
for p in (ROOT/'output/dock-props-436/project'/REL).iterdir():
 if p.name.endswith(('.import','.gd.uid')):
  assert re.search(r'uid://[a-y0-8]+',p.read_text()),p
  (ROOT/REL/p.name).write_bytes(p.read_bytes())
print('Synced only new dock-prop imports and script UID')
