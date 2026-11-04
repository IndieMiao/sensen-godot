"""Stage a pinned b1 copy; factory and approved 1.15m prompt edit are review-only."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tarfile

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/trap-402-v11';PROJECT=OUT/'project'
BASE='174bf1a1027e3bd753f79e41df493d2b3ead3dfa';KIT=ROOT/'assets/props/fish_trap_marker'
PROJECT.mkdir(parents=True,exist_ok=True)
stamp=OUT/'runtime-base.json'
if not stamp.exists():
    proc=subprocess.Popen(['git','archive',BASE,'assets','modules','scenes','addons','project.godot','icon.svg'],cwd=ROOT,stdout=subprocess.PIPE)
    with tarfile.open(fileobj=proc.stdout,mode='r|') as archive:archive.extractall(PROJECT,filter='data')
    assert proc.wait()==0
    critical=['scenes/p0/p0_pond.gd','scenes/p0/p0_ui.gd','modules/p0/p0_trap.gd',
        'modules/fishing/fishing_presentation.gd','modules/fishing/fishing_water.gd',
        'assets/p0/icons/trap_fish.svg','assets/p0/icons/bobber.svg']
    stamp.write_text(json.dumps({'runtime_commit':BASE,'art_base':'caef42a073ce20a7bb16b9414b9026316c9587f6',
        'files':{p:hashlib.sha256((PROJECT/p).read_bytes()).hexdigest() for p in critical if (PROJECT/p).exists()}},indent=2)+'\n')
# Exact requested integration edit, in the output copy only. Restore before each patch for idempotence.
pond_path='scenes/p0/p0_pond.gd'
pond_source=subprocess.check_output(['git','show',BASE+':'+pond_path],cwd=ROOT,text=True)
before='cam.unproject_position(_trap_float.position + Vector3(0, 0.6, 0))'
after='cam.unproject_position(_trap_float.position + Vector3(0, 1.15, 0))'
assert pond_source.count(before)==1
(PROJECT/pond_path).write_text(pond_source.replace(before,after))
snapshot=json.loads(stamp.read_text())
snapshot['review_only_patch']={'path':pond_path,'before':before,'after':after,
    'sha256_after':hashlib.sha256((PROJECT/pond_path).read_bytes()).hexdigest()}
stamp.write_text(json.dumps(snapshot,indent=2)+'\n')
# Raw avatar authoring GLBs reference unbundled source textures; the game uses exported parts instead.
(PROJECT/'assets/avatar/source/.gdignore').touch()
config=KIT/'fish_trap_marker.glb.import'
if not config.exists():
    resource='res://assets/props/fish_trap_marker/fish_trap_marker.glb'
    cache='res://.godot/imported/fish_trap_marker.glb-'+hashlib.md5(resource.encode()).hexdigest()+'.scn'
    config.write_text(f'''[remap]
importer="scene"
importer_version=1
type="PackedScene"
path="{cache}"
[deps]
source_file="{resource}"
dest_files=["{cache}"]
[params]
nodes/root_scale=1.0
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=0
meshes/force_disable_compression=true
animation/import=false
materials/extract=0
gltf/texture_map_mode=1
import_script/path="res://assets/props/fish_trap_marker/material_import.gd"
''')
shutil.copytree(KIT,PROJECT/'assets/props/fish_trap_marker',dirs_exist_ok=True)
for name in ['review.gd','review_pond.gd','configure_imports.gd']:shutil.copy2(SRC/name,PROJECT/name)
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="TrapArtReview" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT/'override.cfg').write_text('''[application]
config/name="SGODOT-402 v1.1 isolated b1 art review"
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenTrap402V11ArtQA"
run/main_scene="res://review.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=960
window/size/viewport_height=900
window/size/window_width_override=960
window/size/window_height_override=900
window/stretch/mode="disabled"
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
textures/vram_compression/import_etc2_astc=false
textures/vram_compression/import_s3tc_bptc=true
[sensen]
network/online_qa=true
network/base_url="http://127.0.0.1:9/v1"
network/mobile_base_url="http://127.0.0.1:9/v1"
''')
print(PROJECT)
