"""Package native proposal views, matched pairs and a labeled top view."""
from pathlib import Path
import hashlib,json,math,re,shutil,subprocess
from PIL import Image,ImageDraw,ImageFont

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
OUT=ROOT/'output/alcatraz-v10-433';REVIEW=OUT/'review'
DOC=ROOT/'docs/design/alcatraz-v10-proposal-433-2026-11-06'
DOC.mkdir(parents=True,exist_ok=True)
plan=json.loads((HERE/'proposal.json').read_text())
validation=json.loads((REVIEW/'proposal-verification.json').read_text())
assert not validation['failures'],validation['failures']
for mode in ['before','after']:
 (DOC/mode).mkdir(exist_ok=True)
 for image in (REVIEW/mode).glob('*.png'):shutil.copy2(image,DOC/mode/image.name)
shutil.copy2(REVIEW/'proposal-verification.json',DOC/'verification.json')
shutil.copy2(OUT/'inputs.json',DOC/'inputs.json')
shutil.copy2(HERE/'proposal.json',DOC/'proposal.json')
font_path='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
font=ImageFont.truetype(font_path,18);small=ImageFont.truetype(font_path,14);large=ImageFont.truetype(font_path,28)
(DOC/'comparisons').mkdir(exist_ok=True)
for name in sorted(p.name for p in (REVIEW/'after').glob('*.png') if p.name!='04-top-layout.png'):
 canvas=Image.new('RGB',(720,840),'#eef0e8');draw=ImageDraw.Draw(canvas)
 for index,mode in enumerate(['before','after']):
  im=Image.open(REVIEW/mode/name).convert('RGB');assert im.size==(360,800)
  canvas.paste(im,(index*360,40))
  suffix='（1.5倍外拉补图）' if name.startswith('02-entry') else '（默认镜头）'
  draw.text((index*360+8,8),('现版' if index==0 else 'v10 方案')+suffix,font=font,fill='#263e45')
 canvas.save(DOC/'comparisons'/name)
# Thumbnail contact sheet; the individual pairs above retain 360x800 pixels.
files=sorted((REVIEW/'after').glob('step*.png'))[:8]
sheet=Image.new('RGB',(180*len(files),860),'#eef0e8');draw=ImageDraw.Draw(sheet)
for column,path in enumerate(files):
 index=int(path.stem.split('-')[1]);distance=path.stem.split('-')[-1]
 for row,mode in enumerate(['before','after']):
  y=row*430;draw.text((column*180+5,y+5),f'第{index+1}屏 / {distance} / '+('现版' if row==0 else '方案'),font=small,fill='#263e45')
  sheet.paste(Image.open(REVIEW/mode/path.name).resize((180,400),Image.Resampling.LANCZOS),(column*180,y+30))
sheet.save(DOC/'route-contact-sheet.png')
image=Image.open(REVIEW/'after/04-top-layout.png').convert('RGB');draw=ImageDraw.Draw(image)
def screen(p):return (500+p[0]*1000/74,600+p[2]*1000/74)
draw.rectangle((16,16,984,122),fill='#eef0e8')
draw.text((32,30),'恶魔岛 v10 方案｜下层观景 + 中层遗迹',font=large,fill='#263e45')
draw.text((32,76),'方案图；现版地形、主路、导航、碰撞保留。上线后的下一版才合。',font=font,fill='#263e45')
route=json.loads((ROOT/'assets/landmarks/alcatraz_island/layout.json').read_text())['route']
for a,b in zip(route,route[1:]):
 a=screen(a);b=screen(b);length=math.dist(a,b)
 for step in range(0,math.ceil(length),12):
  t=step/max(length,1);u=min((step+7)/max(length,1),1)
  draw.line([(a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t),(a[0]+(b[0]-a[0])*u,a[1]+(b[1]-a[1])*u)],fill='#cf6840',width=3)
points=[(-24.4,3.25,6.6),(-14,3.255,5.8),(-7.5,3.28,6.95),(.8,5.5,.35),(-6,5.8,.05)]
for n,p in enumerate(points,1):
 x,y=screen(p);draw.ellipse((x-13,y-13,x+13,y+13),fill='#2a6879',outline='white',width=2)
 draw.text((x-5,y-11),str(n),font=font,fill='white')
old=screen((15.3,3.25,5.95));new=screen(points[3])
draw.ellipse((old[0]-9,old[1]-9,old[0]+9,old[1]+9),outline='#ac5b76',width=3)
draw.line([old,new],fill='#ac5b76',width=3)
a=math.atan2(new[1]-old[1],new[0]-old[0]);draw.polygon([new,(new[0]-14*math.cos(a-.4),new[1]-14*math.sin(a-.4)),(new[0]-14*math.cos(a+.4),new[1]-14*math.sin(a+.4))],fill='#ac5b76')
draw.rectangle((16,997,984,1184),fill='#eef0e8')
legend=['1 西端树荫棚凳 + 望远镜（高件避开操作区）','2 草台内嵌半圆景窗（原主路栏杆碰撞保留，不开新支路）','3 主路上的无字方位圆盘（14.5 mm 饰面）','4 既有倒塌拱券移至中层东侧可见处；东侧旧墙原位保留','5 原花台改碎石野花；赭色虚线 = 既有主路，紫线 = 拱券移位']
for i,line in enumerate(legend):draw.text((32,1012+i*31),line,font=font,fill='#263e45')
image.save(DOC/'top-layout-annotated.png')
# Explicitly prove that staging never wrote back a production resource.
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',plan['base'],'--','assets/landmarks/alcatraz_island','scenes/landmark/alcatraz_island.gd','scenes/landmark/alcatraz_island.tscn','scenes/landmark/alcatraz_island.gd.uid'],text=True).splitlines()
for rel in paths:
 assert (ROOT/rel).read_bytes()==subprocess.check_output(['git','show',plan['base']+':'+rel]),rel
(DOC/'preservation.json').write_text(json.dumps({'passed':True,'base':plan['base'],'production_files_byte_identical':len(paths),'live_collision_shapes_identical':validation['checks']['all_live_collisions_unchanged']['evidence'],'new_tall_hud_probes':'No new overlaps; existing coarse-route candidates preserved exactly.','proposal_only':True},indent=2)+'\n')
media=[]
for path in sorted(DOC.rglob('*.png')):
 with Image.open(path) as im:assert max(im.size)<=1600;size=list(im.size);im.verify()
 media.append({'file':str(path.relative_to(DOC)),'size':size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(DOC/'media-manifest.json').write_text(json.dumps(media,indent=2)+'\n')
print('PACKAGED',len(media),'images;',len(paths),'runtime resources unchanged')
