"""Package v2 native views, full twenty-screen pairs, and a labeled plan."""
from pathlib import Path
import hashlib,json,math,shutil,subprocess
from PIL import Image,ImageDraw,ImageFont
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
OUT=ROOT/'output/alcatraz-v10-433/v2';REVIEW=OUT/'review'
DOC=ROOT/'docs/design/alcatraz-v10-proposal-433-2026-11-06/v2'
DOC.mkdir(parents=True,exist_ok=True)
plan=json.loads((HERE/'proposal.json').read_text());validation=json.loads((REVIEW/'proposal-verification.json').read_text())
assert not validation['failures'],validation['failures']
for mode in ['before','after']:
 (DOC/mode).mkdir(exist_ok=True)
 for path in (REVIEW/mode).glob('*.png'):shutil.copy2(path,DOC/mode/path.name)
for src,dst in [(REVIEW/'proposal-verification.json','verification.json'),(OUT/'inputs.json','inputs.json'),(HERE/'proposal.json','proposal.json'),(OUT/'prototypes/manifest.json','prototype-manifest.json')]:shutil.copy2(src,DOC/dst)
font_path='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
font=ImageFont.truetype(font_path,18);small=ImageFont.truetype(font_path,14);large=ImageFont.truetype(font_path,28)
(DOC/'comparisons').mkdir(exist_ok=True)
for name in sorted(p.name for p in (REVIEW/'after').glob('*.png') if p.name!='04-top-layout.png'):
 canvas=Image.new('RGB',(720,840),'#eef0e8');draw=ImageDraw.Draw(canvas)
 for index,mode in enumerate(['before','after']):
  im=Image.open(REVIEW/mode/name).convert('RGB');assert im.size==(360,800)
  canvas.paste(im,(index*360,40));suffix='（1.5倍外拉）' if name.startswith('02-entry') else '（默认镜头）'
  draw.text((index*360+8,8),('最新基线' if index==0 else 'v10 方案 v2')+suffix,font=font,fill='#263e45')
 canvas.save(DOC/'comparisons'/name)
files=sorted((REVIEW/'after').glob('step*.png'));assert len(files)==20
coverage=[]
for index,path in enumerate(files):
 label=plan['coverage_candidates'].get(str(index))
 coverage.append({'screen':index+1,'route_index':index,'view':path.name,'counted':label is not None,'focal_point':label,
                  'method':'Manual visual assessment of the native frame; repeated views of one landmark and ordinary planting are not added again.'})
assert sum(r['counted'] for r in coverage)>=10
(DOC/'coverage.json').write_text(json.dumps({'counted_screens':sum(r['counted'] for r in coverage),'total_screens':20,'rows':coverage},ensure_ascii=False,indent=2)+'\n')
for batch in range(2):
 group=files[batch*10:(batch+1)*10];sheet=Image.new('RGB',(1440,704),'#eef0e8');draw=ImageDraw.Draw(sheet)
 for col,path in enumerate(group):
  index=int(path.stem.split('-')[1]);distance=path.stem.split('-')[-1]
  for row,mode in enumerate(['before','after']):
   y=row*352;counted=str(index) in plan['coverage_candidates'] and row==1
   draw.text((col*144+4,y+4),f'第{index+1:02d}屏 {distance} '+('前' if row==0 else '后'),font=small,fill='#263e45')
   if counted:draw.rectangle((col*144+2,y+25,col*144+141,y+29),fill='#2b8871')
   sheet.paste(Image.open(REVIEW/mode/path.name).resize((144,320),Image.Resampling.LANCZOS),(col*144,y+32))
 sheet.save(DOC/f'route-contact-sheet-{batch+1}.png')
image=Image.open(REVIEW/'after/04-top-layout.png').convert('RGB');draw=ImageDraw.Draw(image)
def screen(p):return (500+p[0]*1000/74,600+p[2]*1000/74)
def arrow(a,b,color,width=3):
 draw.line([a,b],fill=color,width=width);angle=math.atan2(b[1]-a[1],b[0]-a[0])
 draw.polygon([b,(b[0]-13*math.cos(angle-.4),b[1]-13*math.sin(angle-.4)),(b[0]-13*math.cos(angle+.4),b[1]-13*math.sin(angle+.4))],fill=color)
draw.rectangle((16,16,984,136),fill='#eef0e8')
draw.text((32,29),'恶魔岛 v10 方案 v2｜奶油石栏 + 西向观景',font=large,fill='#263e45')
draw.text((32,75),'基线 4e2c401a：保留已合近远档蓝灰屋顶、观景台 v1.1',font=font,fill='#263e45')
draw.text((32,104),'正式资源未改；原路 / 导航 / 碰撞不变；上线后的下一版才合。',font=font,fill='#263e45')
layout=json.loads((ROOT/'assets/landmarks/alcatraz_island/layout.json').read_text())
for a,b in zip(layout['route'],layout['route'][1:]):
 a=screen(a);b=screen(b);length=math.dist(a,b)
 for step in range(0,math.ceil(length),12):
  t=step/max(length,1);u=min((step+7)/max(length,1),1)
  draw.line([(a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t),(a[0]+(b[0]-a[0])*u,a[1]+(b[1]-a[1])*u)],fill='#cf6840',width=3)
points=[(-25.65,3.25,6.3),(-14,3.25,5.25),(-7.1,3.25,5.47),(.8,5.5,.35),(-6,5.8,.05),(-11.25,5.5,.75),(-19.5,5.5,.65)]
for n,p in enumerate(points,1):
 x,y=screen(p);draw.ellipse((x-12,y-12,x+12,y+12),fill='#2a6879',outline='white',width=2);draw.text((x-5,y-11),str(n),font=font,fill='white')
a=screen(points[0]);arrow((a[0]-5,a[1]+26),(a[0]-95,a[1]+26),'#276f88')
draw.text((a[0]-103,a[1]+36),'−X 海湾',font=font,fill='white')
old=screen((15.3,3.25,5.95));new=screen(points[3]);draw.ellipse((old[0]-8,old[1]-8,old[0]+8,old[1]+8),outline='#ac5b76',width=3);arrow(old,new,'#ac5b76')
draw.rectangle((16,1000,984,1188),fill='#eef0e8')
legend=['1 西向平台外挑约 1.125 m；望远镜与方位盘朝海，铸铁只在平台',
        '2 海鸟栖石　3 无字日晷　4 倒塌拱券；旧墙原位保留',
        '5 粉紫冰花厚垫占位（花台体块不动，碎石恢复原位）',
        '6 低喷泉小景　7 船锚小陈列；新增陈设均在原主路外',
        '全岛主路奶油石栏保留；新增悬挑只作方案展示，不扩可走区']
for i,line in enumerate(legend):draw.text((32,1012+i*32),line,font=font,fill='#263e45')
image.save(DOC/'top-layout-annotated.png')
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',plan['base'],'--','assets/landmarks/alcatraz_island','assets/landmarks/_shared/street_kit','scenes/landmark/alcatraz_island.gd','scenes/landmark/alcatraz_island.tscn','scenes/landmark/alcatraz_island.gd.uid'],text=True).splitlines()
for rel in paths:assert (ROOT/rel).read_bytes()==subprocess.check_output(['git','show',plan['base']+':'+rel]),rel
roof_hashes={name:hashlib.sha256((ROOT/'assets/landmarks/alcatraz_island'/name).read_bytes()).hexdigest() for name in ['alc_museum.glb','alc_museum_far.glb']}
(DOC/'preservation.json').write_text(json.dumps({'passed':True,'base':plan['base'],'production_files_byte_identical':len(paths),'merged_roof_hashes':roof_hashes,'live_collision_shapes_identical':validation['checks']['all_live_collisions_unchanged']['evidence'],'cream_route_rail_replacements':0,'proposal_only':True},indent=2)+'\n')
media=[]
for path in sorted(DOC.rglob('*.png')):
 with Image.open(path) as im:assert max(im.size)<=1600;size=list(im.size);im.verify()
 media.append({'file':str(path.relative_to(DOC)),'size':size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(DOC/'media-manifest.json').write_text(json.dumps(media,indent=2)+'\n')
print('PACKAGED',len(media),'images;',len(paths),'runtime resources unchanged; focal screens',sum(r['counted'] for r in coverage),'/20')
