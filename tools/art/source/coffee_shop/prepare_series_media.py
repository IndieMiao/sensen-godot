from pathlib import Path
from PIL import Image, ImageOps, ImageDraw, ImageFont
import numpy as np,json,subprocess,hashlib,sys,shutil
root=Path.cwd();slug,rev=sys.argv[1:3];doc=root/'docs/design'/(slug+'-2026-10-07');ev=root/'output/scene-bench'/slug/'evidence';out=root/'output'/slug/rev/'delivery';out.mkdir(parents=True,exist_ok=True)
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',22)
def montage(items,name,cols=2):
 w,h=960,770
 canvas=Image.new('RGB',(w*cols,h*((len(items)+cols-1)//cols)),(244,243,237));draw=ImageDraw.Draw(canvas)
 for i,(p,label) in enumerate(items):
  x,y=(i%cols)*w,(i//cols)*h
  im=ImageOps.contain(Image.open(p).convert('RGB'),(w,720))
  canvas.paste(im,(x+(w-im.width)//2,y+45+(720-im.height)//2));draw.text((x+20,y+10),label,fill=(45,55,48),font=font)
 canvas.save(out/name)
montage([(doc/'godot-detail.png','Revised / counter and fixtures'),(doc/'godot-detail-plants.png','Revised / foliage and entrance')],'details.png')
montage([(ev/'spawn.png','Spawn / actual default Avatar'),(ev/'main.png','Counter / actual default Avatar'),(ev/'door.png','Entrance / actual default Avatar'),(ev/'collisions.png','Authored collision shapes')],'character-checks.png')
files=[]
for i,t in enumerate((0,1.5,3,4.5,6,7.5,10,14.5)):
 p=out/f'timeline-{i}.png'
 subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(t),'-i',str(ev/'walkthrough.mp4'),'-frames:v','1',str(p)],check=True)
 files.append((p,f'{t:04.1f}s / real-time viewport'))
montage(files,'video-timeline.jpg',4)
arrays=[np.asarray(Image.open(p).convert('RGB')).astype(float) for p,_ in files]
checks={'black_frames':sum(float(a.mean())<5 for a in arrays),'sample_count':len(files),'motion_max_mean_pixel_delta':max(float(abs(b-a).mean()) for a,b in zip(arrays,arrays[1:])),'duration_seconds':15,'accelerated':False,'sha256':hashlib.sha256((ev/'walkthrough.mp4').read_bytes()).hexdigest()}
assert checks['black_frames']==0 and checks['motion_max_mean_pixel_delta']>0.1
(out/'video-verified.json').write_text(json.dumps(checks,indent=2)+'\n')
print(checks)

shutil.copy2(out/'video-timeline.jpg',doc/'bench-video-timeline.jpg')
