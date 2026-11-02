"""Stage an isolated, desktop-only N5 review; do not touch the main project cache."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[4]
DEST = ROOT / 'output/poi-city-park-320/project'
DEST.mkdir(parents=True, exist_ok=True)


def copy(path):
    src, dst = ROOT/path, DEST/path
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dst, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('*.blend', '*.blend1', '*.py', '__pycache__', 'source'))
    else:
        shutil.copy2(src, dst)


def scene_import(path):
    if path.with_suffix(path.suffix+'.import').exists():return
    resource = 'res://' + str(path.relative_to(ROOT))
    dest = f'res://.godot/imported/{path.name}-{hashlib.md5(resource.encode()).hexdigest()}.scn'
    path.with_suffix(path.suffix+'.import').write_text(f'''[remap]
importer="scene"
importer_version=1
type="PackedScene"
path="{dest}"
[deps]
source_file="{resource}"
dest_files=["{dest}"]
[params]
nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=0
animation/import=false
materials/extract=0
_subresources={{}}
gltf/naming_version=2
gltf/embedded_image_handling=1
gltf/texture_map_mode=1
''')


for directory in ['assets/rooms/poi_city_park', 'assets/rooms/_shared/shell_park']:
    for path in (ROOT/directory).glob('*.glb'):
        scene_import(path)
atlas = ROOT/'assets/rooms/poi_city_park/room_albedo_ao.png'
resource = 'res://' + str(atlas.relative_to(ROOT))
if not atlas.with_suffix('.png.import').exists():atlas.with_suffix('.png.import').write_text(f'''[remap]
importer="texture"
type="CompressedTexture2D"
[deps]
source_file="{resource}"
[params]
compress/mode=2
compress/high_quality=true
mipmaps/generate=true
process/size_limit=0
detect_3d/compress_to=2
''')
for path in json.loads((ROOT/'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text()):
    copy(path.removeprefix('res://'))
for path in ['modules/avatar', 'assets/avatar/demo_denylist.json', 'modules/farm/farm_art.gd',
             'modules/farm/shaders', 'modules/ponds/pond_water.gdshader',
             'assets/ponds/art/pond_ripple_field.png', 'assets/ponds/art/caustic_web.png',
             'assets/farm/art/water/surface_flow.png', 'assets/farm/art/meadow.png',
             'assets/rooms/poi_city_park', 'assets/rooms/_shared/shell_park', 'scenes/poi_city_park']:
    copy(path)
for name in ['deco_bench','deco_fence','tree_0','bush','deco_fountain','deco_birdbath']:
    copy(f'assets/farm/art/{name}.glb')
    copy(f'assets/farm/art/{name}.glb.import')
animation_commit='f4bb293bb8800ca96624912815bc8acae2943285'
animation_bytes=subprocess.check_output(['git','show',animation_commit+':assets/avatar/base/animations.res'],cwd=ROOT)
(DEST/'assets/avatar/base/animations.res').write_bytes(animation_bytes)
(DEST/'animation-provenance.json').write_text(json.dumps({'commit':animation_commit,'file':'assets/avatar/base/animations.res',
    'sha256':hashlib.sha256(animation_bytes).hexdigest(),'seat_root_below_surface_m':.34,'use':'isolated seated review only'},indent=2)+'\n')
manifest=json.loads((ROOT/'assets/avatar/parts_manifest.json').read_text())
manifest['parts']=[p for p in manifest['parts'] if p['id'] in ['body00','eyes00','hairhat0','cloth0','shoes0']]
(DEST/'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(DEST/'project.godot').write_text('''config_version=5
[application]
config/name="SGODOT-320 N5 Art Review"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenCityPark320QA"
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
(DEST/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="CityParkReview" type="Node"]\nscript = ExtResource("1")\n')
shutil.copy2(Path(__file__).with_name('review.gd'),DEST/'review.gd')
shutil.copy2(Path(__file__).with_name('configure_imports.gd'),DEST/'configure_imports.gd')
print(DEST)
