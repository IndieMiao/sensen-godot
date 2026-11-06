"""Copy only this package's Godot-generated imports back from isolated project."""
from pathlib import Path
import re
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/landmarks/alcatraz_island';P=ROOT/'output/alcatraz-ferry-424/project/assets/landmarks/alcatraz_island'
for name in ['ferry.glb.import','ferry_far.glb.import','gull.glb.import','ferry_gull_material_import.gd.uid']:
 text=(P/name).read_text();assert re.search(r'uid://[a-y0-8]+',text),name
 (KIT/name).write_bytes((P/name).read_bytes())
 print('SYNC',name)
