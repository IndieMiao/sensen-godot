"""Capture same-camera actual pendant on/off controls in the isolated R2 project.
Run after render_r1.py r2 clothing_store_a. This never edits scene/benchmark core.
"""
from pathlib import Path
import subprocess,json,sys
root=Path(__file__).resolve().parents[4];out=root/'output/clothing_store_a/r2';stage=out/'godot-project'
s=(root/'tools/art/source/coffee_shop/render_r1.gd').read_text()
start=s.index('\tvar views := [');end=s.index('\tfor view in views:',start)
s=s[:start]+'''\tvar views := []
\tfor label in ["pools-all", "pools-off", "LeftFloorPool", "DisplayTablePool", "RearAislePool"]:
\t\tviews.append([label,_vec(layout.camera.position),_vec(layout.camera.target),float(layout.camera.size)])
'''+s[end:]
s=s.replace('\tfor view in views:\n','''\tfor view in views:
\t\tfor lamp in get_nodes_in_group("street_pendant_pools"):
\t\t\tlamp.visible = view[0] == "pools-all" or str(lamp.name) == view[0]
''')
(stage/'render_pools.gd').write_text(s)
(out/'pool-controls').mkdir(exist_ok=True)
with (out/'pool-render.log').open('w') as log:
 subprocess.run(['godot','--disable-vsync','--max-fps','60','--path',str(stage),'--rendering-method','mobile','--rendering-driver','vulkan','--script','res://render_pools.gd','--','clothing_store_a',str(out/'pool-controls')],stdout=log,stderr=subprocess.STDOUT,check=True)
# Standard Pillow/Numpy only for reporting; pixels come from the live renderer.
import numpy as np,math,hashlib
from PIL import Image,ImageDraw,ImageFont
folder=out/'pool-controls';doc=root/'docs/design/clothing_store_a-2026-10-07'
layout=json.loads((root/'assets/rooms/clothing_store_a/layout.json').read_text());fit=layout['review_camera_fit'];cam=layout['camera'];pitch=math.radians(fit['pitch_degrees']);yaw=math.radians(fit['yaw_degrees']);scale=1400/cam['size']
right=np.array([math.cos(yaw),0,-math.sin(yaw)]);up=np.array([-math.sin(pitch)*math.sin(yaw),math.cos(pitch),-math.sin(pitch)*math.cos(yaw)])
def project(at):
 v=np.array(at)-np.array(cam['target']);return [round(700+v@right*scale),round(700-v@up*scale)]
off=np.array(Image.open(folder/'pools-off.png').convert('RGB')).astype(float);checks=[]
for lamp in layout['pendant_pools']:
 on=np.array(Image.open(folder/(lamp['name']+'.png')).convert('RGB')).astype(float);delta=on-off;x,y=project(lamp['target']);roi=delta[y-24:y+25,x-24:x+25];mean=float(roi.mean());peak=float(roi.max());changed=int((np.max(np.abs(delta),axis=2)>5).sum())
 checks.append({'lamp':lamp['name'],'target_world':lamp['target'],'projected_target_pixel':[x,y],'target_patch_mean_rgb_gain':round(mean,3),'target_patch_peak_gain':round(peak,3),'pixels_delta_over_5':changed,'passed':mean>3 and peak>8,'casts_shadow':False})
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',23);sheet=Image.new('RGB',(2100,1500),'#eee7df');dr=ImageDraw.Draw(sheet)
for i,name in enumerate(['pools-all','pools-off','LeftFloorPool','DisplayTablePool','RearAislePool']):
 im=Image.open(folder/(name+'.png')).convert('RGB');ink=ImageDraw.Draw(im)
 for check in checks:
  if name=='pools-all' or name==check['lamp']:
   x,y=check['projected_target_pixel'];ink.ellipse((x-28,y-28,x+28,y+28),outline='#F56661',width=3)
 x=i%3*700;y=i//3*750;sheet.paste(im.resize((700,700)),(x,y+45));dr.text((x+15,y+10),name,font=font,fill='#38363B')
all_on=np.array(Image.open(folder/'pools-all.png').convert('RGB')).astype(float);diff=np.clip(np.abs(all_on-off)*3,0,255).astype('uint8');sheet.paste(Image.fromarray(diff).resize((700,700)),(1400,795));dr.text((1415,760),'Absolute RGB delta x3 (diagnostic)',font=font,fill='#38363B');sheet.save(doc/'light-pool-controls.jpg',quality=94)
report={'method':'identical camera/renderer; all-on/all-off and each single actual SpotLight3D. Marked 49x49 target patches; diagnostic delta sheet is explicitly labelled.','checks':checks,'passed':all(c['passed'] for c in checks),'source_files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob('*.png')}}
report['whole_capture_rgb_mean_abs_difference']=round(float(np.abs(all_on-np.array(Image.open(out/'godot-whole.png').convert('RGB')).astype(float)).mean()),6)
assert report['whole_capture_rgb_mean_abs_difference'] < .1
(doc/'light-pool-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));assert report['passed']
