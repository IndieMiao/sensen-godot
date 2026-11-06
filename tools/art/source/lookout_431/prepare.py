"""Reuse the verified avatar fixture; add only lookout resources and review code."""
from pathlib import Path
import shutil,hashlib,json,subprocess
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/lookout-431';P=OUT/'project'
REL=Path('assets/landmarks/_shared/street_kit');KIT=ROOT/REL
if not P.exists():shutil.copytree(ROOT/'output/street-kit-429/project',P)
for file in KIT.glob('lookout_*.glb'):
 cfg=Path(str(file)+'.import')
 if not cfg.exists():
  resource='res://'+str(file.relative_to(ROOT));cache=f'res://.godot/imported/{file.name}-{hashlib.md5(resource.encode()).hexdigest()}.scn'
  cfg.write_text(f'''[remap]
importer="scene"
importer_version=1
type="PackedScene"
path="{cache}"
[deps]
source_file="{resource}"
dest_files=["{cache}"]
[params]
nodes/root_script=null
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=1
animation/import=false
gltf/texture_map_mode=1
import_script/path="res://{REL}/street_kit_import.gd"
''')
shutil.copytree(KIT,P/REL,dirs_exist_ok=True)
ref=json.loads((SRC/'provenance.json').read_text())
ground=Path('assets/landmarks/_shared/ground_detail')
if (P/ground).exists():shutil.rmtree(P/ground)
files=subprocess.check_output(['git','ls-tree','-r','--name-only',ref['ground_review_commit'],str(ground)],cwd=ROOT,text=True).splitlines()
for name in files:
 if Path(name).parent!=ground:continue
 target=P/name;target.parent.mkdir(parents=True,exist_ok=True)
 target.write_bytes(subprocess.check_output(['git','show',ref['ground_review_commit']+':'+name],cwd=ROOT))
shutil.copy2(SRC/'review.gd',P/'review.gd')
project=(P/'project.godot').read_text().replace('SensenStreetKit429QA','SensenLookout431QA')
assert 'textures/vram_compression/import_etc2_astc=true' in project
(P/'project.godot').write_text(project)
print(P)
