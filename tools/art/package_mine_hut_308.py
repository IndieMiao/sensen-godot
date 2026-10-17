#!/usr/bin/env python3
"""Package inspected native Godot captures and measured review evidence. Requires Pillow/numpy."""
from pathlib import Path
import json,shutil,hashlib,colorsys,sys,subprocess
from PIL import Image,ImageDraw,ImageFont
import numpy as np
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/minehut-308';DOC=ROOT/'docs/design/mine-hut-308-2026-10-16';KIT=ROOT/'assets/rooms/mine_hut'
if '--anchors' in sys.argv:
 prefix='SGODOT-308_MINEHUT_v1_2_'
 captures=OUT/'captures-v1.2'
 geo=json.loads((OUT/'geometry-validation.json').read_text());godot=json.loads((captures/'godot-validation.json').read_text())
 assert not geo['failures'] and not godot['failures']
 layout=json.loads((KIT/'layout.json').read_text());old=json.loads(subprocess.check_output(['git','show','b848b384:assets/rooms/mine_hut/layout.json'],cwd=ROOT))
 for key in ['local_lights','material_overrides','boundaries','nameplate_clearance','gameplay_camera','camera','review_lighting']:assert layout[key]==old[key],key
 media=[]
 for name in ['ivo_yaw160_43deg_360','standing_clearance_top']:
  src=captures/(name+'.png');dest=DOC/(prefix+src.name);shutil.copy2(src,dest)
  media.append({'file':dest.name,'size':list(Image.open(dest).size),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()})
 for name,asset in geo['assets'].items():assert asset['sha256']==hashlib.sha256((KIT/(name+'.glb')).read_bytes()).hexdigest(),name
 validation={'issue':'SGODOT-308','artist':'Liu Bei / 刘备','virtual_user_id':'0fb1de1f-ead5-443b-9537-54cbac113260','revision':'v1.2 orientation and standing clearance','passed':True,'checks':len(geo['checks'])+len(godot['checks']),'geometry':geo,'godot':godot,'budget':json.loads((KIT/'asset_stats.json').read_text()),'suggested_anchors':layout['suggested_anchors'],'preserved_from_v1_1':['all local lights and material overrides','boundaries and nameplate volume','review and gameplay camera parameters'],'lighting_evidence':'lighting-validation.json records the unchanged lighting parameters at v1.1; no new light-on/off capture in this orientation follow-up.','limits':['Desktop Vulkan Mobile review; no phone performance claim.','Formal runtime anchors and initial camera not edited.']}
 (DOC/'validation.json').write_text(json.dumps(validation,indent=2,ensure_ascii=False)+'\n')
 (DOC/'media-manifest-v1.2.json').write_text(json.dumps(media,indent=2)+'\n')
 print('ANCHOR_PACKAGE',validation['checks'],'checks;',len(media),'images')
 raise SystemExit(0)
PREFIX='SGODOT-308_MINEHUT_v1_1_'
DOC.mkdir(parents=True,exist_ok=True)
for p in (OUT/'captures').glob('*.png'):shutil.copy2(p,DOC/(PREFIX+p.name))
for p in (OUT/'project/assets/rooms/mine_hut').glob('*.import'):shutil.copy2(p,KIT/p.name)
for rel in ['scenes/mine_hut/mine_hut_art.gd.uid']:
 p=OUT/'project'/rel
 if p.exists():shutil.copy2(p,ROOT/rel)
p=OUT/'project/review.gd.uid'
if p.exists():shutil.copy2(p,ROOT/'tools/art/review_mine_hut_308.gd.uid')
ref=Image.open(DOC/'reference.png').convert('RGB');run=Image.open(DOC/(PREFIX+'full_room_panorama.png')).convert('RGB')
canvas=Image.new('RGB',(2454,1354),'#eee8de');canvas.paste(ref,(0,50));canvas.paste(run,(1254,100))
d=ImageDraw.Draw(canvas);font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',24)
d.text((20,12),'STARK REFERENCE / SGODOT-308',font=font,fill='#514437');d.text((1280,12),'GODOT MOBILE v1.1 / LIU BEI / 43 DEG',font=font,fill='#514437')
d.text((20,1312),'Same 6.8 x 6.4 m floor / deeper mine, timber joinery, warm light, thick patched hide and masonry stove base',font=font,fill='#514437')
canvas.save(DOC/(PREFIX+'reference_comparison.png'))
# Same camera/materials: actual warm illumination, not an albedo colour claim.
light_on=np.asarray(run).astype(float)
light_off=np.asarray(Image.open(OUT/'captures/control_local_lights_off.png').convert('RGB')).astype(float)
checks_light=[]
for name,box in [('left_wall',(243,372,282,407)),('stove_floor',(477,449,510,478)),('right_floor',(850,697,878,722))]:
 x0,y0,x1,y1=box;delta=(light_on-light_off)[y0:y1,x0:x1].mean(axis=(0,1))
 checks_light.append({'surface':name,'roi_xyxy':box,'mean_rgb_gain_255':delta.tolist(),'passed':bool(delta.mean()>4 and delta[0]>delta[2])})
lighting={'method':'Identical full-room camera, sun, ambient and emission materials; only layout.local_lights toggled. Declared wall/floor patches must gain >4 RGB/255 mean and more red than blue. This proves local warm pools, not art acceptance or phone performance.','checks':checks_light,'passed':all(c['passed'] for c in checks_light)}
(DOC/'lighting-validation.json').write_text(json.dumps(lighting,indent=2)+'\n')
geo=json.loads((OUT/'geometry-validation.json').read_text());godot=json.loads((OUT/'captures/godot-validation.json').read_text());stats=json.loads((KIT/'asset_stats.json').read_text())
assert not geo['failures'] and not godot['failures'];assert lighting['passed'],lighting
checks=len(geo['checks'])+len(godot['checks'])+len(checks_light)
layout=json.loads((KIT/'layout.json').read_text())
validation={'issue':'SGODOT-308','artist':'Liu Bei / 刘备','virtual_user_id':'0fb1de1f-ead5-443b-9537-54cbac113260','revision':'v1.1','passed':True,'checks':checks,'geometry':geo,'godot':godot,'lighting':lighting,'budget':stats,'suggested_anchors':layout['suggested_anchors'],'limits':['Desktop Vulkan Mobile, AMD Custom GPU 0405 / RADV VANGOGH; no connected Android target for this handoff, no phone performance claim.','Only Ivo and exit are interactive integration suggestions; no runtime anchors or gameplay data edited.','6.72 m native gameplay view deliberately preserves scale and crops room edges; separate 12.4 m panorama includes the complete room.','Art acceptance remains with Huowu; technical review with Shangguan Waner; merge requires user approval.']}
(DOC/'validation.json').write_text(json.dumps(validation,indent=2,ensure_ascii=False)+'\n')
manifest=[]
for p in sorted(DOC.glob(PREFIX+'*.png')):
 im=Image.open(p);manifest.append({'file':p.name,'size':list(im.size),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(DOC/'media-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('PACKAGED',len(manifest),'images;',checks,'checks;',stats['scene_triangles'],'triangles;',stats['static_draw_surfaces'],'surfaces')
