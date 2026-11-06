from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[4];REL=Path('assets/landmarks/_shared/street_kit')
for p in (ROOT/'output/lookout-431/project'/REL).glob('lookout_*.glb.import'):
 assert re.search(r'uid="uid://[a-y0-8]+"',p.read_text()),p
 (ROOT/REL/p.name).write_bytes(p.read_bytes())
print('Synced only five new Godot UID/import files')
