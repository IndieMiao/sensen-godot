from pathlib import Path
import json,hashlib,argparse,shutil
from PIL import Image,ImageDraw,ImageFont
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
a=argparse.ArgumentParser();a.add_argument('--captures',type=Path,required=True);a.add_argument('--version',required=True);a.add_argument('--out',type=Path,required=True);a.add_argument('--stats',type=Path,default=ROOT/'assets/rooms/market_plaza/asset_stats.json');args=a.parse_args();D=args.out;D.mkdir(parents=True,exist_ok=True)
stat=json.loads(args.stats.read_text());rows=stat['assets'];prefix='SGODOT-218_market_props_'+args.version+'_'
font=lambda size:ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',size)
labels={'stall_keeper':'掌柜 Mei 摊','stall_veg':'蔬菜摊','stall_fish':'鱼摊','stall_bakery':'面包摊','stall_spice':'香料摊','stall_tools':'工具摊','flower_cart':'花车','market_board':'委托板','fountain':'两层喷泉','produce_crate':'蔬果箱','basket':'篮子','flower_tub':'花盆（重复摆4件）'}
files=[]
def save(im,suffix):
 p=D/(prefix+suffix+'.png');im.save(p);files.append(p)
def title(im,text,small=''):
 out=Image.new('RGB',(im.width,im.height+72),'#F5F1E9');out.paste(im,(0,72));d=ImageDraw.Draw(out);d.text((20,6),text,font=font(25),fill='#3E493F');d.text((20,41),small,font=font(16),fill='#5D665E');return out
sheet=Image.new('RGB',(1280,3*365+84),'#F5F1E9');draw=ImageDraw.Draw(sheet)
draw.text((20,10),'SGODOT-218 · 集市摊位和小件 · '+args.version,font=font(28),fill='#3E493F')
draw.text((20,49),'实际模型尺寸（宽 × 深 × 高）；人物 1.745 m；Godot Vulkan Mobile；黄忠',font=font(17),fill='#5D665E')
for i,r in enumerate(rows):
 n=r['name'];w,h,d=r['dimensions_m'];info=f'{w:.2f} × {d:.2f} × {h:.2f} m · {r["triangles"]} tris · 1 surface'
 im=Image.open(args.captures/('scale_'+n+'.png')).convert('RGB');im.thumbnail((310,290));x=(i%4)*320;y=84+(i//4)*365;sheet.paste(im,(x+(320-im.width)//2,y))
 draw.text((x+10,y+288),labels[n],font=font(19),fill='#3E493F');draw.text((x+10,y+316),n,font=font(14),fill='#5D665E');draw.text((x+10,y+339),info,font=font(12),fill='#5D665E')
 if not args.version.startswith('blockout'):
  detail=Image.open(args.captures/('detail_'+n+'.png')).convert('RGB');scale=Image.open(args.captures/('scale_'+n+'.png')).convert('RGB');scale.thumbnail((576,640))
  pair=Image.new('RGB',(1216,640),'#F5F1E9');pair.paste(detail,(0,0));pair.paste(scale,(640,0));save(title(pair,n+' · '+labels[n],info+' | yaw 45° / pitch 33° | right: 1.745 m avatar'),n)
save(sheet,'catalogue')
save(title(Image.open(args.captures/'family.png').convert('RGB'),'SGODOT-218 · '+args.version+' · 全家福','12 件独立 GLB；地面仅审阅衬底；人物 1.745 m；黄忠'),'family')
backs=Image.new('RGB',(1500,500),'#F5F1E9');draw=ImageDraw.Draw(backs)
for i,n in enumerate(['stall_keeper','stall_fish','flower_cart']):
 im=Image.open(args.captures/('back20_'+n+'.png')).convert('RGB');im.thumbnail((500,445));backs.paste(im,(500*i,30));draw.text((500*i+15,5),n+' · rear / pitch 20°',font=font(18),fill='#3E493F')
save(backs,'rear_underside')
for src,name in [(args.stats,'asset_stats'),(args.captures/'godot-validation.json','godot_validation'),(args.captures.parent/'geometry-validation.json','geometry_validation')]:
 target=D/(prefix+name+'.json');shutil.copy2(src,target);files.append(target)
(D/'media-manifest.json').write_text(json.dumps([{'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size} for p in files],indent=2)+'\n')
print('packaged',len(files),'files in',D)
