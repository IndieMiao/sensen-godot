"""Stage new props and read-only pinned426/430/432/434 resources for review."""
from pathlib import Path
import json,hashlib,shutil,subprocess
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/dock-props-436';P=OUT/'project'
REL=Path('assets/landmarks/_shared/dock_props');KIT=ROOT/REL
ref=json.loads((SRC/'provenance.json').read_text())
if not P.exists():
 # A clean checkout needs only tracked avatar dependencies, never another output/ folder.
 P.mkdir(parents=True)
 baseline=ref['base_commit']
 def read(path):return subprocess.check_output(['git','show',baseline+':'+path],cwd=ROOT)
 deps=json.loads(read('tools/dev/scene_bench/fixtures/avatar-dependencies.json'))
 files={p.removeprefix('res://') for p in deps}
 files.update(subprocess.check_output(['git','ls-tree','-r','--name-only',baseline,'modules/avatar'],cwd=ROOT,text=True).splitlines())
 files.add('assets/avatar/demo_denylist.json')
 tracked=set(subprocess.check_output(['git','ls-tree','-r','--name-only',baseline,'assets/avatar','modules/avatar'],cwd=ROOT,text=True).splitlines())
 for name in list(files):
  for suffix in ['.import','.uid']:
   if name+suffix in tracked:files.add(name+suffix)
 for name in sorted(files):
  target=P/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(read(name))
 manifest=json.loads(read('assets/avatar/parts_manifest.json'))
 manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
 (P/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2))
 (P/'project.godot').write_text('''config_version=5
[application]
config/name="Dock Props436 Review"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenDockProps436QA"
run/main_scene="res://review.tscn"
boot_splash/show_image=false
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=960
window/size/viewport_height=800
window/size/borderless=true
[rendering]
renderer/rendering_method="mobile"
anti_aliasing/quality/msaa_3d=2
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
for old in [P/'assets/rooms',P/'assets/landmarks']:
 if old.exists():shutil.rmtree(old)
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
import_script/path="res://{REL}/dock_props_import.gd"
''')
shutil.copytree(KIT,P/REL)
hashes={}
for key,dep in ref['dependencies'].items():
 path=Path(dep['path']);files=subprocess.check_output(['git','ls-tree','-r','--name-only',dep['git_ref'],str(path)],cwd=ROOT,text=True).splitlines()
 for file in files:
  if Path(file).parent!=path:continue
  data=subprocess.check_output(['git','show',dep['git_ref']+':'+file],cwd=ROOT);target=P/file;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
  hashes[file]={'git_ref':dep['git_ref'],'sha256':hashlib.sha256(data).hexdigest()}
(OUT/'dependency-hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
shutil.copy2(SRC/'review.gd',P/'review.gd')
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="DockPropsReview" type="Node"]\nscript=ExtResource("1")\n')
project=(P/'project.godot').read_text().replace('SensenLookout431QA','SensenDockProps436QA')
assert 'textures/vram_compression/import_etc2_astc=true' in project
(P/'project.godot').write_text(project)
print(P)
