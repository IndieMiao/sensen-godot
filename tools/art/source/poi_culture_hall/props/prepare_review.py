"""Private prop review; never stages or edits the culture-room assembly."""
from pathlib import Path
import hashlib
import json
import shutil

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
KIT=ROOT/'assets/rooms/poi_culture_hall/props';OUT=ROOT/'output/culture-props-323';DEST=OUT/'project'
DEST.mkdir(parents=True,exist_ok=True)
for path in KIT.glob('*.glb'):
    config=Path(str(path)+'.import')
    if config.exists():continue
    resource='res://'+str(path.relative_to(ROOT));cache=f'res://.godot/imported/{path.name}-{hashlib.md5(resource.encode()).hexdigest()}.scn'
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
meshes/create_shadow_meshes=true
meshes/light_baking=0
animation/import=false
materials/extract=0
gltf/texture_map_mode=1
import_script/path="res://assets/rooms/poi_culture_hall/props/material_import.gd"
''')
def copy(relative):
    source=ROOT/relative;target=DEST/relative;target.parent.mkdir(parents=True,exist_ok=True)
    if source.is_dir():shutil.copytree(source,target,dirs_exist_ok=True)
    else:
        shutil.copy2(source,target)
        for suffix in ['.import','.uid']:
            if Path(str(source)+suffix).exists():shutil.copy2(Path(str(source)+suffix),Path(str(target)+suffix))
copy('assets/rooms/poi_culture_hall/props')
for path in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):copy(path.removeprefix('res://'))
copy('modules/avatar');copy('assets/avatar/demo_denylist.json')
manifest=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())
manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(DEST/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for name in ['review.gd','configure_imports.gd']:shutil.copy2(SRC/name,DEST/name)
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="CulturePropsReview" type="Node"]\nscript=ExtResource("1")\n')
(DEST/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-323 Props Review"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenCulture323PropsQA"
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
print(DEST)
