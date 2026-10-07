"""Stage a tiny art-only Godot project; no gameplay benchmark or export preset."""
from pathlib import Path
import json
import shutil
import sys

ROOT=Path(__file__).resolve().parents[2]
slug=sys.argv[1]
out=ROOT/'output'/(slug+'-2026-10-07')
project=out/'godot-project'
for folder in ['assets/rooms/'+slug,'scenes/'+slug]:
    shutil.copytree(ROOT/folder,project/folder,dirs_exist_ok=True)
layout=json.loads((ROOT/'assets/rooms'/slug/'layout.json').read_text())
if layout.get('effects'):
    shutil.copytree(ROOT/'assets/rooms/_shared/fx',project/'assets/rooms/_shared/fx',dirs_exist_ok=True)
    shutil.copytree(ROOT/'scenes/room_effects',project/'scenes/room_effects',dirs_exist_ok=True)
if layout.get('shared_plants'):
    shutil.copytree(ROOT/'assets/rooms/_shared/plants',project/'assets/rooms/_shared/plants',dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('source'))
(project/'tools/art').mkdir(parents=True,exist_ok=True)
shutil.copy2(ROOT/'tools/art/review_room.gd',project/'tools/art/review_room.gd')
(project/'project.godot').write_text('''config_version=5
[application]
config/name="Room art inspection"
[display]
window/size/viewport_width=720
window/size/viewport_height=540
[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_etc2_astc=true
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
''')
# Configure texture importer after the initial import and then reimport.
print(project)
