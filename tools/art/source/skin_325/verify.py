"""Verify immutable A inputs, exact approved palette, switch paths and imports."""
from pathlib import Path
import hashlib
import json
import subprocess
import re
import numpy as np
from PIL import Image

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[3]
OUT = ROOT / 'output/skin-325-v1'
PROJECT = OUT / 'project'
BASE = '0edd0fc1d3bacdc2ec7657c895da66488f70ddfb'
report = {'base_commit': BASE, 'checks': [], 'original_files': {}, 'images': {}}

def check(ok, label):
    report['checks'].append({'check': label, 'passed': bool(ok)})
    if not ok:
        print('FAIL', label)

def digest(data):
    return hashlib.sha256(data).hexdigest()

paths = ['assets/rooms/poi_hotel_lobby', 'assets/rooms/poi_service_hall',
         'assets/rooms/_shared/shell_hall', 'assets/rooms/_shared/plants',
         'scenes/poi_hotel_lobby', 'scenes/poi_service_hall', 'scenes/shell_hall']
files = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE, '--', *paths], cwd=ROOT, text=True).splitlines()
for name in files:
    baseline = subprocess.check_output(['git', 'show', BASE + ':' + name], cwd=ROOT)
    actual = (ROOT / name).read_bytes()
    report['original_files'][name] = {'base_sha256': digest(baseline), 'current_sha256': digest(actual)}
check(all(v['base_sha256'] == v['current_sha256'] for v in report['original_files'].values()),
      'Every original room/shared asset, scene and layout remains byte-identical to branch base')
report['original_glbs'] = len([name for name in files if name.endswith('.glb')])
slots = json.loads((ROOT/'assets/rooms/_shared/shell_hall/hall_palette.json').read_text())['slots']
uids = []
for room in ['poi_hotel_lobby', 'poi_service_hall']:
    kit = ROOT / 'assets/rooms' / room
    manifest = json.loads((kit / 'variants.json').read_text())
    delivered = [kit/'variants.json',kit/'room_albedo_ao_b.png',kit/'sign_b.png',
                 kit/'room_albedo_ao_b.png.import',kit/'sign_b.png.import',*sorted((kit/'variants').rglob('*.tscn'))]
    check(all(p.read_bytes() == (PROJECT/p.relative_to(ROOT)).read_bytes() for p in delivered),
          room + ': delivered resources match the actual rendered project bytes')
    a_name = 'room_albedo_ao.png' if room == 'poi_hotel_lobby' else 'hall_albedo_ao_n2.png'
    a = np.array(Image.open(kit / a_name).convert('RGBA'))
    b = np.array(Image.open(kit / 'room_albedo_ao_b.png').convert('RGBA'))
    check(b.shape == (2048,2048,4), room + ': 2048 square B atlas')
    check(np.array_equal(a[:,:,3],b[:,:,3]), room + ': atlas alpha unchanged')
    mock = ROOT / 'output/skin-325-mock/project/mock' / room / 'room_albedo_ao_b.png'
    if mock.exists():
        check((kit/'room_albedo_ao_b.png').read_bytes() == mock.read_bytes(), room + ': exact approved v0.1 atlas bytes')
    retained = ['linen','porcelain','print_portrait','print_landscape','sky','glass','leaf','leaf_light','leaf_dark'] if room == 'poi_hotel_lobby' else ['print_portrait','linen_green','accent_gold','terra_light','glass']
    for slot in retained:
        x,y,w,h = slots[slot]['rect_px_top_left']
        check(np.array_equal(a[y:y+h,x:x+w], b[y:y+h,x:x+w]), room + ': retained ' + slot)
    if room == 'poi_service_hall':
        for tile in json.loads((kit/'room_skin.json').read_text())['plant_tiles']:
            x,y = tile['target_px']
            check(np.array_equal(a[y:y+128,x:x+128],b[y:y+128,x:x+128]), 'N2 plant tile ' + str([x,y]))
    check(manifest['variants']['A']['atlas'] == a_name and manifest['default_variant'] == 'A', room + ': A is still default')
    check(manifest['variants']['A']['enabled_options'] == [], room + ': no B options in A')
    expected_sign = [1.6,.22] if room == 'poi_hotel_lobby' else [.66,.23]
    check(manifest['variants']['B']['sign']['size_m'] == expected_sign, room + ': approved v1.1 writing area')
    check(manifest['variants']['B']['sign']['offset_m'] == ([0,0,.009] if room == 'poi_hotel_lobby' else [.1,0,.009]), room + ': approved room-space text offset')
    for option in manifest['options'].values():
        check((kit/option['scene']).is_file(), room + ': switch resource exists ' + option['scene'])
    for name in ['room_albedo_ao_b.png','sign_b.png']:
        source = (kit/(a_name+'.import')).read_text()
        imported = (kit/(name+'.import')).read_text()
        uid = re.search(r'uid="([^"]+)"', imported)[1]
        uids.append(uid)
        expected_params = source.split('[params]',1)[1].strip()
        if name == 'sign_b.png':expected_params = re.sub(r'detect_3d/compress_to=\d+', 'detect_3d/compress_to=2', expected_params)
        check(imported.split('[params]',1)[1].strip() == expected_params, room + ': inherited import params with approved sign compression for ' + name)
        check(uid != re.search(r'uid="([^"]+)"',source)[1], room + ': independent texture uid ' + name)
        report['images'][str((kit/name).relative_to(ROOT))] = {'sha256':digest((kit/name).read_bytes()),'uid':uid}
    sign = np.array(Image.open(kit/'sign_b.png').convert('RGB'))
    if room == 'poi_hotel_lobby':
        check(np.unique(sign.reshape(-1,3),axis=0).shape[0] == 1, 'N1 entire sign has no baked text or marks')
    else:
        check(sign.shape == (230,880,3), 'N2 patch aspect matches .88 x .23m plaque interior')
        check(np.unique(sign[:,210:870].reshape(-1,3),axis=0).tolist() == [[247,251,247]], 'N2 0.66 x 0.23 m writing region at +X .10 is completely blank')
        check(np.unique(sign.reshape(-1,3),axis=0).tolist() == [[62,158,106],[247,251,247]], 'N2 sign contains only white and approved green cross')
check(len(uids) == len(set(uids)), 'All four new texture UIDs are distinct')
options = json.loads((OUT/'options-validation.json').read_text())
check(options['passed'], 'Offline option geometry checks passed')
report['options_geometry'] = {key:options[key] for key in ['niches','checks','passed']}
report['passed'] = all(c['passed'] for c in report['checks'])
(OUT/'preservation-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(len(report['checks']), 'checks; preserved', len(files), 'files /', report['original_glbs'], 'GLBs; passed:', report['passed'])
raise SystemExit(0 if report['passed'] else 1)
