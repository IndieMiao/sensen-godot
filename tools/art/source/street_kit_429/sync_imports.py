from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[4];REL=Path('assets/landmarks/_shared/street_kit')
for p in (ROOT/'output/street-kit-429/project'/REL).iterdir():
 if p.name.endswith(('.import','.gd.uid')):
  assert re.search(r'uid://[a-y0-8]+',p.read_text()),p
  (ROOT/REL/p.name).write_bytes(p.read_bytes())
print('Copied only street-kit Godot-generated UIDs/imports')
