"""Prepare isolated review project and pinned read-only #830 ground fixture."""
from pathlib import Path
import json,hashlib,shutil,subprocess
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
REL=Path('assets/landmarks/_shared/street_kit');KIT=ROOT/REL
OUT=ROOT/'output/street-kit-429';P=OUT/'project'
GROUND=Path('assets/landmarks/_shared/ground_detail')
ref=json.loads((SRC/'reference/provenance.json').read_text())
if not P.exists():shutil.copytree(ROOT/'output/church-kit-427-v11/project',P)
# The benchmark's avatar remains; older environment assets are hidden only here.
for path in [P/'assets/rooms',P/'assets/landmarks']:
 if path.exists():shutil.rmtree(path)
for file in KIT.glob('*.glb'):
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
shutil.copytree(KIT,P/REL)
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',ref['ground_review_commit'],str(GROUND)],cwd=ROOT,text=True).splitlines()
hashes={}
for path in paths:
 data=subprocess.check_output(['git','show',ref['ground_review_commit']+':'+path],cwd=ROOT)
 target=P/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data);hashes[path]=hashlib.sha256(data).hexdigest()
(OUT/'ground-fixture-hashes.json').write_text(json.dumps({'commit':ref['ground_review_commit'],'files':hashes},indent=2)+'\n')
for file in SRC.glob('*.gd'):shutil.copy2(file,P/file.name)
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="StreetKitReview" type="Node"]\nscript=ExtResource("1")\n')
project=(P/'project.godot').read_text().replace('SensenChurchKit423QA','SensenStreetKit429QA')
project=project.replace('textures/vram_compression/import_etc2_astc=false','textures/vram_compression/import_etc2_astc=true')
assert 'textures/vram_compression/import_etc2_astc=true' in project
(P/'project.godot').write_text(project)
print(P)
