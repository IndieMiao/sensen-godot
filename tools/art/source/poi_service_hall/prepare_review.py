"""Stage two neutral blockouts, using immutable shared shell and hallkit files."""
from pathlib import Path
import json
import shutil
from dependencies import ROOT,SRC,OUT,DEPS,HALL

DEST=OUT/'project'
DEST.mkdir(parents=True,exist_ok=True)


def copy(path,base=ROOT):
    source=base/path;target=DEST/path
    target.parent.mkdir(parents=True,exist_ok=True)
    if source.is_dir():
        shutil.copytree(source,target,dirs_exist_ok=True,ignore=shutil.ignore_patterns('source','*.blend','*.py','__pycache__'))
    else:shutil.copy2(source,target)


for path in [HALL,'scenes/shell_hall']:copy(path,DEPS)
for path in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):copy(path.removeprefix('res://'))
for path in ['modules/avatar','assets/avatar/demo_denylist.json','assets/rooms/_shared/plants/peace_lily.glb']:copy(path)
manifest=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())
manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(DEST/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for name in ['blockout_layouts.json','measured_dependencies.json','dependency_manifest.json','review.gd']:
    shutil.copy2(SRC/name,DEST/name)
(DEST/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-321 N2 Blockout Review"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenServiceHall321BlockoutQA"
boot_splash/show_image=false
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=960
window/size/viewport_height=800
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
''')
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="ServiceHallBlockout" type="Node"]\nscript = ExtResource("1")\n')
print(DEST)
