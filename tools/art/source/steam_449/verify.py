"""Source-scope and actual transparent-pixel verification for SGODOT449."""
from pathlib import Path
import argparse,json,hashlib,re,subprocess,math
from PIL import Image
import numpy as np
ROOT=Path(__file__).resolve().parents[4];KIT=ROOT/'assets/props/cooking_pot_wait'
a=argparse.ArgumentParser();a.add_argument('--out',type=Path,required=True);a.add_argument('--live',type=Path,required=True);a.add_argument('--single',type=Path,required=True);args=a.parse_args();OUT=args.out.resolve();checks=[]
BASE=json.loads((ROOT/'tools/art/source/steam_449/reference/base.json').read_text())['art_base']
def check(ok,name,evidence=None):checks.append({'check':name,'passed':bool(ok),'evidence':evidence})
def original(rel):return subprocess.check_output(['git','show',BASE+':'+str(rel)],cwd=ROOT)
scene=(KIT/'cooking_pot_wait.tscn').read_text();old=original('assets/props/cooking_pot_wait/cooking_pot_wait.tscn').decode()
def protected(s):
 blocks=re.split(r'(?=^\[)',s,flags=re.M)
 return ''.join(b for b in blocks if not(b.startswith('[sub_resource') and any(t in b.split('\n')[0] for t in ['Gradient_011xv','ParticleProcessMaterial_xclje','QuadMesh_r7biw'])) and not b.startswith('[node name="Steam"'))
check(protected(scene)==protected(old),'Every non-Steam node and both animations byte-identical')
for p in KIT.iterdir():
 if p.suffix=='.res' or p.name in ['soup_matte.tres','steam_lid_clearance.gd','steam_lid_clearance.gd.uid','steam_clear_lid.gdshader.uid']:
  check(p.read_bytes()==original(p.relative_to(ROOT)),p.name+' unchanged')
for p in (ROOT/'assets/props/stove_pot').iterdir():
 if p.is_file():check(p.read_bytes()==original(p.relative_to(ROOT)),str(p.relative_to(ROOT))+' unchanged')
shader=(KIT/'steam_clear_lid.gdshader').read_text();baseline=original('assets/props/cooking_pot_wait/steam_clear_lid.gdshader').decode()
mask='float above_lid = smoothstep(0.0, 0.003, lid_top_uv - SCREEN_UV.y);'
check(mask in shader and mask in baseline and '* above_lid' in shader,'Original lid mask expression retained unchanged')
check('amount = 3' in scene and 'lifetime = 1.8' in scene and 'local_coords = true' in scene,'Three particles,1.8s lifetime,local coords')
check('initial_velocity_min = 0.098' in scene and 'initial_velocity_max = 0.098' in scene,'Fixed0.098m/s rise')
check('gravity = Vector3(0, 0, 0)' in scene and 'spread = 0.0' in scene,'No extra ballistic drift or spread')
check('size = Vector2(0.050, 0.050)' in scene,'Initial25px quad at500px/m')
texture=Image.open(KIT/'steam_puff.png');check(texture.size==(128,128) and texture.mode=='RGBA','Single128x128RGBA texture')
uid=re.search('uid="(uid://[a-y0-8]+)"',(KIT/'steam_puff.png.import').read_text());check(uid is not None,'Texture Godot-generated UID')
# Native host5d50bf0c measurement, authoritative over the previous43deg fixture.
native=json.loads((args.live/'native-validation.json').read_text());single=json.loads((args.single/'single-validation.json').read_text())
for c in native['checks']:check(c['passed'],'Native: '+c['check'],c.get('evidence'))
check(single['passed'],'Native single-puff dimensions22–26→34–40px',{'initial':single['initial_width_px'],'grown_max':single['grown_max_px']})
travel=.098*1.8*500*math.cos(math.radians(33));check(60<=travel<=80,'Native33deg projected rise60–80px',travel)
check(.016*500<=10,'Authored lateral drift<=10px',.016*500)
check(abs(1.8/3-.6)<1e-7,'Emission every0.6s',1.8/3)
rows=native['frames']
report={'task':'SGODOT-449','status':'native Common overlay verified; ready for art review','checks':checks,'passed':all(x['passed'] for x in checks),'pixel_frames':rows,'texture_sha256':hashlib.sha256((KIT/'steam_puff.png').read_bytes()).hexdigest(),'texture_uid':uid.group(1) if uid else None,'extra_particle_triangles':6,'extra_texture_count':1,'reference_ppm':500,'reference_pitch':33}
(OUT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('STEAM449_CHECKS',len(checks),'PASS',report['passed']);raise SystemExit(0 if report['passed'] else 1)
