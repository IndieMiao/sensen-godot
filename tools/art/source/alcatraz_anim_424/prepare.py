"""Stage a private continuation of the pinned b16c3198 ferry review fixture."""
from pathlib import Path
import shutil,hashlib,re,json
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];O=ROOT/'output/alcatraz-anim-424';P=O/'project';K=ROOT/'assets/landmarks/alcatraz_island';REL=K.relative_to(ROOT)
if not P.exists():shutil.copytree(ROOT/'output/alcatraz-ferry-424/project',P)
for n in ['gull','ferry','ferry_far','ferry_flag']:
 cfg=K/(n+'.glb.import')
 if not cfg.exists():
  r='res://'+str(REL/(n+'.glb'));cache=f'res://.godot/imported/{n}.glb-{hashlib.md5(r.encode()).hexdigest()}.scn'
  cfg.write_text(f'[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath="{cache}"\n[deps]\nsource_file="{r}"\ndest_files=["{cache}"]\n[params]\nnodes/root_script=null\nnodes/root_scale=1.0\nmeshes/ensure_tangents=true\nmeshes/generate_lods=false\nmeshes/light_baking=1\nanimation/import=false\ngltf/texture_map_mode=1\nimport_script/path="res://{REL}/ferry_gull_material_import.gd"\n')
 for ext in ['.glb','.glb.import']:shutil.copy2(K/(n+ext),P/REL/(n+ext))
for name in ['ferry_gull_material_import.gd','ferry_gull_material_import.gd.uid','ferry_gull_manifest.json']:
 shutil.copy2(K/name,P/REL/name)
for s in SRC.glob('*.gd'):shutil.copy2(s,P/s.name)
(P/'project.godot').write_text((P/'project.godot').read_text().replace('SensenAlcatrazFerry424QA','SensenAlcatrazAnim424QA'))
print(P)
