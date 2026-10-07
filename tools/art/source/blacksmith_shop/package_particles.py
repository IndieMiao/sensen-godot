from pathlib import Path
import json,subprocess,hashlib,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];out=ROOT/'output/blacksmith_shop/r22';doc=ROOT/'docs/design/blacksmith_shop-2026-10-07';font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',21)
records=[];canvas=Image.new('RGB',(1800,1905),'#eee7df');draw=ImageDraw.Draw(canvas)
for row,name in enumerate(['whole-motion','fire-motion','smoke-motion']):
 frames=[]
 for col,time in enumerate([.25,4,7.5]):
  dest=out/(name+f'-sample-{col}.jpg');subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(time),'-i',str(out/(name+'.mp4')),'-frames:v','1',str(dest)],check=True)
  im=Image.open(dest).convert('RGB');frames.append(np.array(im).astype(float));canvas.paste(im.resize((600,600)),(col*600,row*635+35));draw.text((col*600+10,row*635+7),name+f' / {time}s real-time',font=font,fill='#443b37')
 records.append({'file':name+'.mp4','sha256':hashlib.sha256((out/(name+'.mp4')).read_bytes()).hexdigest(),'sampled_black_frames':sum(bool(a.mean()<5) for a in frames),'max_pixel_delta':max(float(abs(a-b).mean()) for a,b in zip(frames,frames[1:]))})
 assert records[-1]['sampled_black_frames']==0 and records[-1]['max_pixel_delta']>.05
canvas.save(doc/'particles-video-timeline.jpg',quality=93)
clips=json.loads((out/'particle-clips.json').read_text());stats=json.loads((ROOT/'assets/rooms/blacksmith_shop/asset_stats.json').read_text());render=json.loads((out/'godot-verification.json').read_text())
result={'revision':'R2.2','effects':stats['effects'],'clips':clips,'video_verification':records,'whole_scene_draw_calls_R21':21,'whole_scene_draw_calls_R22':next(v['draw_calls'] for v in render['views'] if v['view']=='godot-whole'),'static_surfaces':18,'particle_surfaces':3,'standalone_validation':json.loads((ROOT/'output/shared-fx/test-result.json').read_text()),'limits':'Desktop Mobile/Vulkan only. Particle videos are real-time viewport capture, not hardware GPU performance data. 236 is gated on art-director approval; Basic Room has not changed.'}
(doc/'particles-verification.json').write_text(json.dumps(result,indent=2)+'\n');print('PARTICLE_MEDIA_VERIFIED',records)
