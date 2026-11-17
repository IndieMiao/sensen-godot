"""Copy exact demo/bridge/view sources into an isolated no-autoload QA project."""
import hashlib
import json
import pathlib
import shutil
import sys
repo = pathlib.Path(__file__).resolve().parents[2]
target = pathlib.Path(sys.argv[1]).resolve()
if target == repo or repo in target.parents:
    raise SystemExit('QA target must be outside the repository')
marker = target / '.geofarm-qa'
if target.exists() and any(target.iterdir()) and not marker.exists():
    raise SystemExit('Refusing an unowned target')
target.mkdir(parents=True, exist_ok=True)
marker.touch()
paths = list((repo / 'demo/geofarm').glob('*.gd*')) + list((repo / 'demo/geofarm').glob('*.tscn'))
paths += list((repo / 'scenes/geo_farm_demo').glob('farm_*'))
paths += [repo / 'scenes/map_poc' / name for name in ['map_bridge.gd','map_bridge_android.gd']]
paths += list((repo / 'tests/geofarm').glob('*.gd*'))
manifest = {}
for path in paths:
    rel = path.relative_to(repo)
    (target / rel).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, target / rel)
    manifest[str(rel)] = hashlib.sha256(path.read_bytes()).hexdigest()
(target / 'source-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n')
(target / 'project.godot').write_text('''config_version=5
[application]
config/name="GeoFarm Map QA"
config/use_custom_user_dir=true
config/custom_user_dir_name="pangu-geofarm-map-qa-1117"
run/main_scene="res://demo/geofarm/geofarm_main.tscn"
[display]
window/size/viewport_width=360
window/size/viewport_height=800
window/stretch/mode="canvas_items"
[rendering]
renderer/rendering_method="gl_compatibility"
textures/default_filters/use_nearest_mipmap_filter=false
''')
print(target)
