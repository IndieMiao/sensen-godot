"""Stage an isolated static-kit review from the unmodified runtime branch."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[4]
SRC = Path(__file__).resolve().parent
RUNTIME = ROOT / 'output/monsters-355/runtime'
parser = argparse.ArgumentParser()
parser.add_argument('group', choices=['headgear', 'mine_props'])
args = parser.parse_args()
OUT = ROOT / 'output/mine-kit-355' / args.group
PROJECT = OUT / 'project'
PROJECT.mkdir(parents=True, exist_ok=True)
classes = {}
for folder in ['modules', 'scenes']:
    for path in (RUNTIME / folder).rglob('*.gd'):
        match = re.search(r'^class_name\s+(\w+)', path.read_text(), re.M)
        if match:
            classes[match.group(1)] = path.relative_to(RUNTIME)
queue = [Path(p) for p in ['modules/mining/mine_art.gd', 'modules/mining/mine_combat.gd',
    'modules/farm/farm_camera.gd', 'modules/avatar/avatar_service.gd',
    'assets/avatar/demo_denylist.json', 'assets/monsters/material_import.gd']]
queue += [Path(p.removeprefix('res://')) for p in json.loads(
    (ROOT / 'tools/dev/scene_bench/fixtures/avatar-dependencies.json').read_text())]
queue += [p.relative_to(RUNTIME) for p in (RUNTIME / 'modules/avatar').rglob('*.gd')]
queue += [Path('assets/ui/icons/lucide/' + name + '.svg') for name in ['circle-check', 'circle', 'chevron-down']]
seen = set()
while queue:
    rel = queue.pop()
    source = RUNTIME / rel
    if rel in seen or not source.is_file():
        continue
    seen.add(rel)
    target = PROJECT / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    for suffix in ['.import', '.uid']:
        side = Path(str(source) + suffix)
        if side.exists():
            shutil.copy2(side, Path(str(target) + suffix))
    if source.suffix in ['.gd', '.tscn', '.tres', '.gdshader']:
        text = source.read_text()
        queue += [Path(p) for p in re.findall(r'res://([^"\s]+)', text) if not p.endswith('/')]
        queue += [path for name, path in classes.items() if re.search(r'\b' + name + r'\b', text)]

directories = ['assets/monsters/slime_king'] if args.group == 'headgear' else ['assets/mine/rocks', 'assets/mine/props']
for directory in directories:
    model_dir = RUNTIME / directory
    for model in model_dir.glob('*.glb'):
        config = Path(str(model) + '.import')
        if not config.exists():
            resource = 'res://' + directory + '/' + model.name
            cache = 'res://.godot/imported/' + model.name + '-' + hashlib.md5(resource.encode()).hexdigest() + '.scn'
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
nodes/use_name_suffixes=true
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=0
animation/import=false
animation/remove_immutable_tracks=false
materials/extract=0
gltf/texture_map_mode=1
import_script/path="res://assets/monsters/material_import.gd"
_subresources={{}}
''')
    shutil.copytree(model_dir, PROJECT / directory, dirs_exist_ok=True)

manifest = json.loads((RUNTIME / 'assets/avatar/parts_manifest.json').read_text())
manifest['parts'] = [p for p in manifest['parts'] if p['id'] in ['body00', 'eyes00', 'hairhat0', 'cloth0', 'shoes0']]
(PROJECT / 'assets/avatar/parts_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
shutil.copy2(SRC / (args.group + '_review.gd'), PROJECT / 'review.gd')
(PROJECT / 'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="StaticKitReview" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT / 'project.godot').write_text(f'''config_version=5
[application]
config/name="SGODOT-355 {args.group} review"
run/main_scene="res://review.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenMineKit355_{args.group}"
boot_splash/show_image=false
[autoload]
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=800
window/size/viewport_height=700
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_s3tc_bptc=true
lights_and_shadows/directional_shadow/size=2048
''')
base = subprocess.check_output(['git', '-C', str(RUNTIME), 'rev-parse', 'HEAD'], text=True).strip()
(OUT / 'dependencies.json').write_text(json.dumps({'runtime_base': base, 'files': {
    str(p): hashlib.sha256((RUNTIME / p).read_bytes()).hexdigest() for p in sorted(seen)}}, indent=2) + '\n')
print(PROJECT, len(seen), 'unmodified dependencies')
