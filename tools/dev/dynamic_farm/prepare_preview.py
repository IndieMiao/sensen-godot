"""Stage an offline preview using existing imported artifacts. Never invokes editor/import."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
parser.add_argument('--cache-root', required=True)
parser.add_argument('--copy-tests', action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[3]
out = Path(args.output).resolve()
cache = Path(args.cache_root).resolve()
if out == repo or repo in out.parents:
    raise SystemExit('Use an independent temporary project outside the worktree')
out.mkdir(parents=True, exist_ok=True)
for name in ['modules', 'scenes', 'assets', 'tests', 'tools']:
    link = out / name
    if name == 'tests' and args.copy_tests:
        if link.is_symlink(): link.unlink()
        shutil.copytree(repo / name, link, dirs_exist_ok=True, ignore=shutil.ignore_patterns('__pycache__'))
        continue
    if not link.exists():
        link.symlink_to(repo / name, target_is_directory=True)
    elif link.resolve() != repo / name:
        raise SystemExit('Staging destination already contains another project')
state = out / '.godot'
(state / 'imported').mkdir(parents=True, exist_ok=True)
for source in (cache / '.godot/imported').iterdir():
    if source.is_file():
        dest = state / 'imported' / source.name
        if not dest.exists(): dest.symlink_to(source)
for name in ['global_script_class_cache.cfg', 'uid_cache.bin']:
    source = cache / '.godot' / name
    if source.exists(): shutil.copy2(source, state / name)
# Verify the approved source assets and their existing remaps before any Godot run.
inventory = json.loads((repo / 'assets/dynamic_farm/499-art-inventory.json').read_bytes())
evidence = []
for asset in inventory['assets']:
    source = repo / asset['path'].removeprefix('res://')
    meta = Path(str(source) + '.import')
    assert hashlib.sha256(source.read_bytes()).hexdigest() == asset['sha256'], source.name
    assert hashlib.sha256(meta.read_bytes()).hexdigest() == asset['import_sha256'], meta.name
    target = re.search(r'^path="res://(.+)"', meta.read_text(), re.M).group(1)
    if not (out / target).exists(): raise SystemExit('Missing existing imported asset: ' + asset['id'])
    evidence.append({'id': asset['id'], 'source_sha256': asset['sha256'], 'imported': target})
(out / 'prepared-assets.json').write_text(json.dumps(evidence, indent=2))
(out / 'qa_router.gd').write_text('extends Node\nvar sync_loads := RenderingServer.get_current_rendering_method() == \"gl_compatibility\"\n')
(out / 'project.godot').write_text('''config_version=5
[application]
config/name="Dynamic Farm QA"
config/features=PackedStringArray("4.7", "Mobile")
config/use_custom_user_dir=true
config/custom_user_dir_name="SensenDynamicFarmQA"
[autoload]
GlesColour="*res://modules/render/gles_albedo.gd"
GlesSunShadows="*res://modules/ui/gles_sun_shadows.gd"
AppRouter="*res://qa_router.gd"
Avatar="*res://modules/avatar/avatar_service.gd"
[display]
window/size/viewport_width=360
window/size/viewport_height=640
window/size/window_width_override=720
window/size/window_height_override=1280
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
[input_devices]
pointing/emulate_mouse_from_touch=true
pointing/android/enable_pan_and_scale_gestures=true
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
anti_aliasing/quality/msaa_3d=2
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
''')
print('Prepared offline scene; no Godot/import/export/ADB run:', out)
