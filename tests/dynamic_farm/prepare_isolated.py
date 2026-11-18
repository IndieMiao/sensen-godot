"""Prepare exact host/map code with no production autoloads, tokens or endpoints."""
import hashlib
import json
from pathlib import Path
import shutil
import sys

repo = Path(__file__).resolve().parents[2]
target = Path(sys.argv[1]).resolve()
if target == repo or repo in target.parents:
    raise SystemExit('Target must be outside repository')
marker = target / '.dynamic-preview-qa'
if target.exists() and any(target.iterdir()) and not marker.exists():
    raise SystemExit('Refusing unowned target')
target.mkdir(parents=True, exist_ok=True)
marker.touch()
files = []
for folder in ['modules/dynamic_farm', 'scenes/dynamic_farm', 'tests/dynamic_farm']:
    files += [p for p in (repo / folder).rglob('*') if p.is_file() and p.suffix in ['.gd', '.tscn', '.uid']]
files += [repo / 'scenes/map_poc' / name for name in ['map_bridge.gd', 'map_bridge_android.gd']]
hashes = {}
for path in files:
    rel = path.relative_to(repo)
    dest = target / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dest)
    hashes[str(rel)] = hashlib.sha256(path.read_bytes()).hexdigest()
(target / 'source-sha256.json').write_text(json.dumps(hashes, indent=2) + '\n')
(target / 'project.godot').write_text('''config_version=5
[application]
config/name="Dynamic Farm Host QA"
config/use_custom_user_dir=true
config/custom_user_dir_name="pangu-dynamic-host-qa-1118"
[display]
window/size/viewport_width=360
window/size/viewport_height=800
[sensen]
network/online_qa=true
[rendering]
renderer/rendering_method="gl_compatibility"
''')
print(target)
