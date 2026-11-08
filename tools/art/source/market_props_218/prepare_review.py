"""Stage only this kit and existing avatar fixtures into an isolated review project."""
from pathlib import Path
import argparse,shutil,hashlib
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];REL=Path('assets/rooms/market_plaza')
p=argparse.ArgumentParser();p.add_argument('--template',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args();P=a.out.resolve()/'project'
P.mkdir(parents=True,exist_ok=True)
for path in ['assets/avatar','modules/avatar']:
 if not (P/path).exists():shutil.copytree(a.template/path,P/path)
for path in (ROOT/REL).glob('*.glb'):
 cfg=Path(str(path)+'.import')
 if not cfg.exists():
  res='res://'+str(path.relative_to(ROOT));cache=f'res://.godot/imported/{path.name}-{hashlib.md5(res.encode()).hexdigest()}.scn'
  cfg.write_text(f'''[remap]
importer="scene"
importer_version=1
type="PackedScene"
path="{cache}"
[deps]
source_file="{res}"
dest_files=["{cache}"]
[params]
nodes/root_script=null
nodes/root_scale=1.0
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=0
animation/import=false
gltf/texture_map_mode=1
''')
shutil.copytree(ROOT/REL,P/REL,dirs_exist_ok=True)
shutil.copy2(SRC/'review.gd',P/'review.gd')
(P/'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="MarketPropReview" type="Node"]\nscript=ExtResource("1")\n')
(P/'project.godot').write_text('''config_version=5
[application]
config/name="Market218PropReview"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="Market218PropReview"
run/main_scene="res://review.tscn"
boot_splash/show_image=false
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=800
window/size/viewport_height=800
window/size/borderless=true
[rendering]
renderer/rendering_method="mobile"
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
''')
print(P)
