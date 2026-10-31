"""Isolated prop review and fixed-object occlusion fixture, without a B room assembly."""
import hashlib
import json
from pathlib import Path
import shutil
from dependencies import ROOT,SRC,OUT,DEPS,HALL

DEST=OUT/'details_project'
DEST.mkdir(parents=True,exist_ok=True)
KIT=ROOT/'assets/rooms/poi_service_hall'
for path in KIT.glob('*.glb'):
    imported=path.with_suffix('.glb.import')
    if imported.exists():continue
    resource='res://'+str(path.relative_to(ROOT))
    cached=f'res://.godot/imported/{path.name}-{hashlib.md5(resource.encode()).hexdigest()}.scn'
    imported.write_text(f'''[remap]
importer="scene"
importer_version=1
type="PackedScene"
path="{cached}"
[deps]
source_file="{resource}"
dest_files=["{cached}"]
[params]
nodes/root_scale=1.0
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=0
animation/import=false
materials/extract=0
gltf/texture_map_mode=1
''')
atlas=KIT/'hall_albedo_ao_n2.png.import'
if not atlas.exists():atlas.write_text('''[remap]
importer="texture"
type="CompressedTexture2D"
[deps]
source_file="res://assets/rooms/poi_service_hall/hall_albedo_ao_n2.png"
[params]
compress/mode=2
compress/high_quality=true
mipmaps/generate=true
detect_3d/compress_to=2
''')


def copy(path,base=ROOT):
    source=base/path;target=DEST/path
    target.parent.mkdir(parents=True,exist_ok=True)
    if source.is_dir():shutil.copytree(source,target,dirs_exist_ok=True)
    else:shutil.copy2(source,target)


for path in [HALL,'scenes/shell_hall']:copy(path,DEPS)
copy('assets/rooms/poi_service_hall')
for path in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):copy(path.removeprefix('res://'))
copy('modules/avatar');copy('assets/avatar/demo_denylist.json')
manifest=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())
manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(DEST/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for name in ['details_review.gd','configure_details.gd']:shutil.copy2(SRC/name,DEST/name)
(DEST/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-321 Detailed Props Review"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenServiceHall321PropsQA"
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
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://details_review.gd" id="1"]\n[node name="N2Props" type="Node"]\nscript = ExtResource("1")\n')
print(DEST)
