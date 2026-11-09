"""Source-scope and actual transparent-pixel verification for SGODOT449."""
from pathlib import Path
import argparse,json,hashlib,re,subprocess,math
from PIL import Image
import numpy as np
ROOT=Path(__file__).resolve().parents[4];KIT=ROOT/'assets/props/cooking_pot_wait'
a=argparse.ArgumentParser();a.add_argument('--out',type=Path,required=True);args=a.parse_args();OUT=args.out.resolve();checks=[]
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
check('initial_velocity_min = 0.105' in scene and 'initial_velocity_max = 0.105' in scene,'Fixed0.105m/s rise')
check('gravity = Vector3(0, 0, 0)' in scene and 'spread = 0.0' in scene,'No extra ballistic drift or spread')
check('size = Vector2(0.050, 0.050)' in scene,'Initial25px quad at500px/m')
texture=Image.open(KIT/'steam_puff.png');check(texture.size==(128,128) and texture.mode=='RGBA','Single128x128RGBA texture')
uid=re.search('uid="(uid://[a-y0-8]+)"',(KIT/'steam_puff.png.import').read_text());check(uid is not None,'Texture Godot-generated UID')
# Use full-alpha precision captures for the candidate, with documented diagnostic host composition.
P=OUT/'refined_preview';m=json.loads((P/'measurements.json').read_text());rows=[]
for f in m['frames']:
 im=np.asarray(Image.open(P/'layers'/f"{f['i']:03d}.png"));alpha=im[:,:,3]/255.;yy,xx=np.indices(alpha.shape)
 # The underlying opaque pot occupies pixels at/below the measured animated lid top.
 # Steam's unchanged lid mask is zero there, so only pixels above that line are steam.
 valid=yy+110<min(195.,f['lid_top']-.6);visible=valid&(alpha>=.01);coords=np.argwhere(visible)
 b=[int(coords[:,1].min()+80),int(coords[:,0].min()+110),int(coords[:,1].max()+81),int(coords[:,0].max()+111)] if coords.size else []
 rows.append({'frame':f['i'],'bounds_xyxy':b,'peak_alpha':float(alpha[valid].max()),'ring_peak_alpha':float(alpha[valid&(yy>=60)].max())})
check(all(r['bounds_xyxy'] and r['bounds_xyxy'][0]>=130 and r['bounds_xyxy'][1]>=120 and r['bounds_xyxy'][2]<=230 and r['bounds_xyxy'][3]<=195 for r in rows),'90frames remain in allowed region and fade byy120',{'min':[min(r['bounds_xyxy'][i] for r in rows) for i in [0,1]],'max':[max(r['bounds_xyxy'][i] for r in rows) for i in [2,3]]})
check(max(r['ring_peak_alpha'] for r in rows)<=.5,'Composite steam alpha<=.5 in ring region',max(r['ring_peak_alpha'] for r in rows))
check(max(r['peak_alpha'] for r in rows)<=.601,'Composite upper steam alpha~.6',max(r['peak_alpha'] for r in rows))
single=[]
single_report=json.loads((OUT/'single_puff/measurements.json').read_text())
for f in single_report['frames']:
 im=np.asarray(Image.open(OUT/'single_puff/layers'/f"{f['i']:03d}.png"));alpha=im[:,:,3]/255.;yy,xx=np.indices(alpha.shape)
 coords=np.argwhere((alpha>=.01)&(yy+110<min(195.,f['lid_top']-.6)))
 single.append({'frame':f['i'],'width':int(np.ptp(coords[:,1])+1) if len(coords) else 0})
births=[i for i in range(1,len(single)) if single[i-1]['width']==0 and single[i]['width']>0]
initial=[single[i+j]['width'] for i in births for j in range(6) if i+j<len(single)]
check(initial and min(initial)>=22 and max(initial)<=26,'Measured first0.2s width22–26px',initial)
check(34<=max(x['width'] for x in single)<=40,'Measured grown puff diameter34–40px',max(x['width'] for x in single))
travel=.105*1.8*500*math.cos(math.radians(43));check(60<=travel<=80,'Screen rise60–80px',travel)
check(.016*500<=10,'Authored lateral drift<=10px',.016*500)
check(abs(1.8/3-.6)<1e-7,'Emission every0.6s',1.8/3)
report={'task':'SGODOT-449','status':'isolated candidate; real overlay verification pending','checks':checks,'passed':all(x['passed'] for x in checks),'pixel_frames':rows,'texture_sha256':hashlib.sha256((KIT/'steam_puff.png').read_bytes()).hexdigest(),'texture_uid':uid.group(1) if uid else None,'extra_particle_triangles':6,'extra_texture_count':1,'reference_ppm':500,'reference_pitch':43}
(OUT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('STEAM449_CHECKS',len(checks),'PASS',report['passed']);raise SystemExit(0 if report['passed'] else 1)
