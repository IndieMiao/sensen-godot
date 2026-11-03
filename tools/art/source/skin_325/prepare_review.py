"""Read-only staging of approved N1/N2 sources; all changes stay in output."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/skin-325-v1';PROJECT=OUT/'project'
PROJECT.mkdir(parents=True,exist_ok=True)
folders=['assets/rooms/poi_hotel_lobby','assets/rooms/poi_service_hall','assets/rooms/_shared/shell_hall',
    'assets/rooms/_shared/plants','assets/rooms/_shared/fx','scenes/poi_hotel_lobby','scenes/poi_service_hall','scenes/shell_hall','modules/avatar']
hashes={}
def copy(relative):
    source=ROOT/relative;target=PROJECT/relative
    if source.is_dir():
        for path in source.rglob('*'):
            if path.is_file() and 'source' not in path.relative_to(source).parts and path.suffix!='.blend':copy(path.relative_to(ROOT))
    else:
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
        hashes[str(relative)]=hashlib.sha256(source.read_bytes()).hexdigest()
for folder in folders:copy(Path(folder))
for resource in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):
    relative=Path(resource.removeprefix('res://'));copy(relative)
    for suffix in ['.import','.uid']:
        if (ROOT/Path(str(relative)+suffix)).exists():copy(Path(str(relative)+suffix))
copy(Path('assets/avatar/demo_denylist.json'))
manifest=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())
manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(PROJECT/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
shutil.copy2(ROOT/'docs/design/poi-hotel-lobby-319-2026-10-31/native-camera-n1-v1.1.json',PROJECT/'n1-camera.json')
for filename in ['review.gd','build_options.gd','configure_imports.gd']:
    shutil.copy2(SRC/filename,PROJECT/filename)
(PROJECT/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-325 isolated B v1 review"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenSkin325V1Review"
boot_splash/show_image=false
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=1000
window/size/viewport_height=900
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
''')
(PROJECT/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="SkinReview" type="Node"]\nscript=ExtResource("1")\n')
(OUT/'source-snapshot.json').write_text(json.dumps({'base_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
    'files':hashes},indent=2)+'\n')
print(PROJECT,len(hashes),'source files copied; original files untouched')
