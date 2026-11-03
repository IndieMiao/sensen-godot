"""Copy only newly generated B resources out of the isolated authoring project."""
from pathlib import Path
import json
import shutil

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[3]
OUT = ROOT / 'output/skin-325-v1'
PROJECT = OUT / 'project'
assert json.loads((OUT / 'options-validation.json').read_text())['passed']
for room in ['poi_hotel_lobby', 'poi_service_hall']:
    relative = Path('assets/rooms') / room
    source = PROJECT / relative
    target = ROOT / relative
    for name in ['room_albedo_ao_b.png.import', 'sign_b.png.import', 'variants.json']:
        shutil.copy2(source / name, target / name)
    shutil.copytree(source / 'variants', target / 'variants', dirs_exist_ok=True)
print('Collected B options, manifest and four new texture imports; no A or GLB writes')
