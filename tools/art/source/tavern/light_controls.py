"""Capture actual local-light on/off controls in the same camera and materials."""
from pathlib import Path
import sys,json,subprocess
from PIL import Image,ImageDraw,ImageFont,ImageOps
import numpy as np
ROOT=Path(__file__).resolve().parents[4];slug=sys.argv[1];rev=sys.argv[2] if len(sys.argv)>2 else 'r2';out=ROOT/'output'/slug/rev;stage=out/'godot-project';doc=ROOT/'docs/design'/(slug+'-2026-10-07')
s=(ROOT/'tools/art/source/coffee_shop/render_r1.gd').read_text()
a=s.index('\tvar views := [');b=s.index('\tfor view in views:',a)
s=s[:a]+'''\tvar views := [["local-lights-on",_vec(layout.camera.position),_vec(layout.camera.target),float(layout.camera.size)],["local-lights-off",_vec(layout.camera.position),_vec(layout.camera.target),float(layout.camera.size)]]
'''+s[b:]
s=s.replace('\t\tcamera.position = view[1]', '\t\tfor light in get_nodes_in_group("art_local_lights"): light.visible = view[0] == "local-lights-on"\n\t\tcamera.position = view[1]')
if slug=='blacksmith_shop':s=s.replace('light.visible = view[0] == "local-lights-on"','light.visible = view[0] == "local-lights-on" and light.name == "LocalLight_forge_fire"')
s=s.replace('output_dir + "/godot-verification.json"','output_dir + "/light-control-render.json"')
probes={'tavern':[('Wall sconce',[-3.49,2.07,2.10]),('Bar candle',[-.56,1.402,-1.25]),('Table lantern',[-2.35,1.293,.98])], 'blacksmith_shop':[('Anvil face',[.05,1.725,1.28]),('Workbench',[-.73,1.137,1.32]),('Floor',[-.8,.083,-.35])]}[slug]
insert='\tvar samples: Array = []\n'
for name,xyz in probes:insert+='\tsamples.append({"name":'+json.dumps(name)+',"position":'+str(xyz)+',"pixel":camera.unproject_position(Vector3('+','.join(map(str,xyz))+'))})\n'
insert+='\tvar sample_file := FileAccess.open(output_dir + "/light-probes.json",FileAccess.WRITE)\n\tsample_file.store_string(JSON.stringify(samples))\n'
s=s.replace('\tquit()',insert+'\tquit()');(stage/'light_controls.gd').write_text(s)
with (out/'light-controls.log').open('w') as log:subprocess.run(['godot','--disable-vsync','--max-fps','60','--path',str(stage),'--rendering-method','mobile','--rendering-driver','vulkan','--script','res://light_controls.gd','--',slug,str(out)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=60)
on=Image.open(out/'local-lights-on.png').convert('RGB');off=Image.open(out/'local-lights-off.png').convert('RGB');a=np.array(on).astype(float);b=np.array(off).astype(float)
checks=[];records=json.loads((out/'light-probes.json').read_text());font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',22)
for rec in records:
 x,y=map(lambda x:int(float(x)),rec['pixel'].strip('()').split(', '));radius=8
 delta=(a[y-radius:y+radius+1,x-radius:x+radius+1]-b[y-radius:y+radius+1,x-radius:x+radius+1]);gain=float(delta.mean())
 checks.append({'name':rec['name'],'position':rec['position'],'pixel':[x,y],'patch_size':17,'mean_rgb_255_gain':round(gain,3),'passed':gain>1})
 for im in (on,off):dr=ImageDraw.Draw(im);dr.rectangle((x-radius,y-radius,x+radius,y+radius),outline='#e62f63',width=3)
canvas=Image.new('RGB',(2800,1480),'#eee7df');canvas.paste(on,(0,55));canvas.paste(off,(1400,55));dr=ImageDraw.Draw(canvas)
dr.text((20,15),'Forge light ONLY / exact review camera' if slug=='blacksmith_shop' else 'Local lights ON / exact review camera',font=font,fill='#443b37');dr.text((1420,15),'Local lights OFF / same emission, materials, sun and ambient',font=font,fill='#443b37')
for i,c in enumerate(checks):dr.text((20+i*900,1450),c['name']+': +'+str(c['mean_rgb_255_gain'])+' RGB/255',font=font,fill='#443b37')
canvas.save(doc/'light-pool-controls.jpg',quality=93)
layout=json.loads((ROOT/'assets/rooms'/slug/'layout.json').read_text());result={'checks':checks,'passed':all(c['passed'] for c in checks),'lights':layout['local_lights'],'local_light_count':len(layout['local_lights']),'all_local_shadows':False,'method':'Same camera/materials; forge light alone vs all local lights off; lantern and hot-steel lights stay off in both controls.' if slug=='blacksmith_shop' else 'Same camera/materials, all local Omni lights on vs off; 17x17 mean RGB around declared physical surface positions; emission remains enabled.'}
(doc/'light-pool-verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));assert result['passed']
