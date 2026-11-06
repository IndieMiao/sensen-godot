"""Update only the near museum roof, retaining the existing editable island.

flock ~/gs66-render.lock blender --background --threads 3 --python-exit-code 1 \
  --python "$PWD/tools/art/source/alcatraz_island/build_museum_roof.py"
"""
from pathlib import Path
import hashlib
import json
import sys
import bpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = ROOT/'assets/landmarks/alcatraz_island'
sys.path[:0] = [str(ROOT/'tools/art'), str(HERE)]
from landmark_kit import Kit
import museum_roof

bpy.ops.wm.open_mainfile(filepath=str(HERE/'alcatraz_blockout.blend'))
bpy.context.preferences.filepaths.save_version = 0
# Work on the module library: assembly instances remain untouched.
library = bpy.data.scenes['Alcatraz_Module_Library']
bpy.context.window.scene = library
collection = bpy.data.collections['alc_museum']
vents_only = '--vents-only' in sys.argv
for obj in list(collection.objects):
    selected = obj.name.startswith('roof_vent_') if vents_only else museum_roof.is_roof_part(obj.name)
    if selected:
        bpy.data.objects.remove(obj, do_unlink=True)
kit = Kit(OUT, {})
kit.current = collection
kit.assets['alc_museum'] = collection
kit.no_ao.add('alc_museum')
(museum_roof.build_vents if vents_only else museum_roof.build)(kit, kit.box)
stats = kit.export('alc_museum')
data = (OUT/'alc_museum.glb').read_bytes()
stats['sha256'] = hashlib.sha256(data).hexdigest()
manifest = json.loads((OUT/'manifest.json').read_text())
manifest['assets']['alc_museum'].update(stats)
(OUT/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
preserved = json.loads((HERE/'preserved_geometry.json').read_text())
preserved['assets']['alc_museum'] = stats
preserved['reason'] = 'Five owned modules retain b81605af; alc_museum uses the roof-only revision documented in museum_roof_contract.json. --layout-only preserves all six current GLBs.'
(HERE/'preserved_geometry.json').write_text(json.dumps(preserved, indent=2)+'\n')
contract = {
    'scope': 'Near museum roof decoration only; far LOD assigned to Huang Zhong after handoff',
    'baseline': '02d5534768fc1a5557feaecb705b8f445562fd6b',
    'asset': 'alc_museum.glb', 'stats': stats,
    'units': 'metres, Godot Y-up, local ground centre; front +Z',
    'placement': [0, 10, -13], 'envelope': [40, 9.18, 10],
    'building_envelope_without_vents': [40, 9, 10],
    'vent_revision_baseline': '4a47e6223903e4adb504dfd738bbb0ab2cb63a27',
    'colors_srgb': museum_roof.COLORS,
    'skylights': [{'centre_xz': list(p), 'curb_size_xz': [3.8, 2.0],
                   'base_y': 8.62, 'top_y': 9.0} for p in museum_roof.SKYLIGHT_CENTRES],
    'vents': [{'centre_xz': list(p), 'scale_from_v1': museum_roof.VENT_SCALE,
               'body_size_xyz': [.96, .45, .96], 'body_center_y': 8.865,
               'cap_size_xyz': [1.23, .09, 1.23], 'cap_center_y': 9.135,
               'inset_size_xyz': [.57, .1425, .018], 'inset_center_y': 8.91,
               'inset_offset_z': .489, 'body_bevel_m': .03, 'cap_bevel_m': .018,
               'base_y': museum_roof.VENT_BASE_Y, 'top_y': 9.18} for p in museum_roof.VENT_CENTRES],
    'coping': {'top_y': 8.96, 'height': .06, 'width': .32},
    'material': 'One opaque matte vertex-colour surface; no textures or transparency',
}
(HERE/'museum_roof_contract.json').write_text(json.dumps(contract, indent=2)+'\n')
bpy.context.window.scene = next(s for s in bpy.data.scenes if s != library)
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'alcatraz_blockout.blend'))
print('MUSEUM_ROOF_EXPORTED', json.dumps(stats), flush=True)
