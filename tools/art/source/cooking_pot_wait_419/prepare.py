"""Stage the unchanged b1 runtime plus only this prop for offline art review."""
from pathlib import Path
import hashlib, json, shutil, subprocess, tarfile

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[3]
OUT = ROOT / 'output/cookpot-419'
PROJECT = OUT / 'project'
BASE = '67116c6df4f69062ce658c50581e72ab1779a1b4'
PROJECT.mkdir(parents=True, exist_ok=True)
if not (OUT / 'runtime-base.json').exists():
    proc = subprocess.Popen(['git', 'archive', BASE, 'assets', 'modules', 'scenes', 'addons', 'project.godot', 'icon.svg'], cwd=ROOT, stdout=subprocess.PIPE)
    with tarfile.open(fileobj=proc.stdout, mode='r|') as archive:
        archive.extractall(PROJECT, filter='data')
    assert proc.wait() == 0
    (OUT / 'runtime-base.json').write_text(json.dumps({'runtime_commit': BASE}, indent=2)+'\n')
    cache = ROOT / 'output/gathered-417/project/.godot'
    if cache.exists():
        shutil.copytree(cache, PROJECT / '.godot', dirs_exist_ok=True)
(PROJECT / 'assets/avatar/source/.gdignore').touch()
asset = ROOT / 'assets/props/cooking_pot_wait'
asset.mkdir(parents=True, exist_ok=True)
shutil.copytree(asset, PROJECT / 'assets/props/cooking_pot_wait', dirs_exist_ok=True)
for p in SRC.glob('*.gd'):
    shutil.copy2(p, PROJECT / p.name)
(PROJECT / 'review.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://review.gd" id="1"]\n[node name="CookingPotReview" type="Node"]\nscript=ExtResource("1")\n')
(PROJECT / 'override.cfg').write_text('''[application]
config/name="SGODOT-419 isolated art review"
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenCooking419ArtQA"
run/main_scene="res://review.tscn"
[editor_plugins]
enabled=PackedStringArray()
[display]
window/size/viewport_width=720
window/size/viewport_height=800
window/size/window_width_override=720
window/size/window_height_override=800
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
original = 'assets/props/stove_pot/stove_pot.glb'
assert (ROOT/original).read_bytes() == (PROJECT/original).read_bytes()
print('STAGED', PROJECT, 'SOURCE_POT_SHA256', hashlib.sha256((ROOT/original).read_bytes()).hexdigest())
