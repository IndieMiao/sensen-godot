from pathlib import Path
import json,hashlib,subprocess
import numpy as np
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];O=ROOT/'output/alcatraz-anim-424';C=O/'captures';D=ROOT/'docs/design/alcatraz-anim-424-2026-11-06';D.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';font=lambda n:ImageFont.truetype(FONT,n)
PREFIX='SGODOT-424_anim_v1_';contact=C/'contact_frames';contact.mkdir(exist_ok=True)
report=json.loads((C/'godot-validation.json').read_text());assert report['passed']
for i in range(180):
 canvas=Image.new('RGB',(1200,800),'#EAE6DC');d=ImageDraw.Draw(canvas);canvas.paste(Image.open(C/'opening_frames'/f'{i:04}.png'),(0,0))
 d.text((372,7),'黄忠 · 原点位的三只海鸥 / 渡轮动作补充视角',font=font(20),fill='#34444A')
 for j in range(3):
  canvas.paste(Image.open(C/f'gull{j}_frames'/f'{i:04}.png'),(360+j*280,40))
  d.text((372+j*280,285),f'Gull {j+1} · offset {report["phase_offsets"][j]:.2f}s',font=font(15),fill='#34444A')
 canvas.paste(Image.open(C/'ferry_frames'/f'{i:04}.png'),(360,320))
 d.text((372,793-18),'左：原生码头开场｜右：原地近景，不改摆位｜6 s / 30 fps',font=font(16),fill='#34444A')
 canvas.save(contact/f'{i:04}.png')
for source,name in [('opening_frames','opening_6s'),('contact_frames','all_motion_6s')]:
 subprocess.run(['ffmpeg','-y','-loglevel','error','-framerate','30','-i',str(C/source/'%04d.png'),'-frames:v','180','-c:v','libx264','-crf','18','-preset','medium','-pix_fmt','yuv420p','-movflags','+faststart',str(D/(PREFIX+name+'.mp4'))],check=True)
canvas=Image.new('RGB',(1160,336),'#EAE6DC');d=ImageDraw.Draw(canvas);d.text((12,8),'黄忠 · 海鸥原地 idle（8.5 s）｜同一网格 284 面，脚和根节点不动',font=font(22),fill='#34444A')
for i,(name,label,t) in enumerate([('stand','站立',0),('turn_head','转头',1.65),('preen','理毛',4),('spread','轻扑翅',6.48)]):
 canvas.paste(Image.open(C/('pose_'+name+'.png')),(10+i*290,48));d.text((20+i*290,298),f'{label} · {t:.2f} s',font=font(20),fill='#34444A')
meta=PngImagePlugin.PngInfo();meta.add_text('Author','黄忠 / 5281cd25-6a49-4df8-9802-f3e534956e80');canvas.save(D/(PREFIX+'gull_poses.png'),pnginfo=meta)
# Read the encoded streams and count decoded frames; preserve evidence for review.
videos=[]
for name in ['opening_6s','all_motion_6s']:
 file=D/(PREFIX+name+'.mp4');probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-count_frames','-show_streams','-show_format','-of','json',str(file)]));stream=probe['streams'][0]
 assert int(stream['nb_read_frames'])==180 and abs(float(probe['format']['duration'])-6)<.01
 subprocess.run(['ffmpeg','-v','error','-i',str(file),'-f','null','-'],check=True)
 videos.append({'file':file.name,'frames':int(stream['nb_read_frames']),'duration_s':float(probe['format']['duration']),'width':stream['width'],'height':stream['height'],'frame_rate':stream['r_frame_rate'],'decoded_without_error':True})
validation={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','geometry':json.loads((O/'geometry-validation.json').read_text()),'godot':report,'videos':videos,'fixture':'b16c3198 host with #815 accepted meshes plus animation scenes, original point coordinates, camera and bridge. Only local temporary replacement.','rendering_note':'Deterministic Godot animation times sampled at 30fps, encoded to normal-speed 6s videos. Not realtime GPU throughput or phone performance.'}
old=np.array(Image.open(ROOT/'docs/design/alcatraz-ferry-424-2026-11-06/SGODOT-424_ferry_gull_v1_opening_360.png').convert('RGB'))
new=np.array(Image.open(C/'opening_frames/0000.png').convert('RGB'));diff=np.abs(old[55:145,:120].astype(int)-new[55:145,:120].astype(int))
assert not diff.any();validation['approved_bridge_control']={'baseline':'#815 opening_360.png','roi':[0,55,120,90],'max_channel_difference':int(diff.max()),'different_pixels':int((diff.max(2)>0).sum())}
(D/(PREFIX+'validation.json')).write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
(D/'media-manifest.json').write_text(json.dumps([{'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size} for p in sorted(D.glob(PREFIX+'*'))],indent=2)+'\n')
# End/start/middle contact sheet for actual review of encoded result.
for frame in [0,90,179]:
 subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(D/(PREFIX+'all_motion_6s.mp4')),'-vf',f'select=eq(n\\,{frame})','-frames:v','1',str(O/f'encoded_{frame:03d}.png')],check=True)
print('PACKAGED',videos)
