"""Package exact 360x800 farm captures, labels and audit evidence; no repainting."""
from pathlib import Path
import json,hashlib,shutil
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];QA=ROOT/'output/homestead-439';DST=ROOT/'docs/design/homestead-looks-439/v1.1';DST.mkdir(parents=True,exist_ok=True)
RAW=DST/'raw';RAW.mkdir(exist_ok=True);DATA=DST/'validation';DATA.mkdir(exist_ok=True)
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def font(n):return ImageFont.truetype(FONT,n)
def label(im,title,note):
 d=ImageDraw.Draw(im);d.rounded_rectangle((10,149,350,191),6,fill=(249,246,230));d.text((18,152),title,font=font(15),fill=(50,48,38));d.text((18,174),note,font=font(11),fill=(74,73,61))
 d.rounded_rectangle((211,682,350,701),4,fill=(249,246,230));d.text((217,683),'SGODOT-439 · 【赵云】',font=font(11),fill=(50,48,38))
media=[]
def save(im,name):
 p=DST/name;im.save(p);media.append({'name':name,'path':str(p.relative_to(ROOT)),'mime':'image/png','size':list(im.size),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
sheet=Image.new('RGB',(1080,1600));titles=['现在','加门廊 · Lv5 外观','加扩建 · Lv8 外观']
for r,look in enumerate(['a','b']):
 for c,stage in enumerate(['current','porch','kitchen']):
  p=QA/(look+'_'+stage+'.png');shutil.copy2(p,RAW/p.name);im=Image.open(p).convert('RGB');assert im.size==(360,800)
  label(im,look+' '+('木作' if look=='a' else '石作')+' / '+titles[c],'同一 Lv8 场地 · 原生默认开场 43° · 360×800')
  sheet.paste(im,(c*360,r*800))
save(sheet,'SGODOT-439_HOMESTEAD_v1.1_three_stages.png')
close=Image.new('RGB',(720,800))
for i,look in enumerate(['a','b']):
 p=QA/(look+'_sign_view.png');shutil.copy2(p,RAW/p.name);im=Image.open(p).convert('RGB');label(im,look+' '+('木作' if look=='a' else '石作')+' / 门牌视角','真实农场 43° · zoom 1.2 · 近景隐藏人物')
 close.paste(im,(360*i,0))
save(close,'SGODOT-439_HOMESTEAD_v1.1_sign_view.png')
for suffix,title,note in [('yaw45','水平角 45°','真实农场 · 俯角43° · zoom1.2 · 补充方向'),('rear225','后侧检查','225° / 43° · 临时隐藏遮窗树 · 核对侧 / 背窗')]:
 im=Image.new('RGB',(720,800))
 for i,look in enumerate(['a','b']):
  p=QA/(look+'_'+suffix+'.png');shutil.copy2(p,RAW/p.name);panel=Image.open(p).convert('RGB');label(panel,look+' '+('木作' if look=='a' else '石作')+' / '+title,note);im.paste(panel,(360*i,0))
 save(im,'SGODOT-439_HOMESTEAD_v1.1_'+suffix+'.png')
for name in ['asset-validation.json','render-validation.json','footprint-validation.json','palette-validation.json','native-layout.json','stage.json']:
 shutil.copy2(QA/name,DATA/name)
shutil.copy2(QA/'preview.patch',DATA/'preview.patch')
for name in ['asset-validation.json','render-validation.json','footprint-validation.json']:assert json.loads((DATA/name).read_text())['passed']
(DST/'media-manifest.json').write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print('PACKAGED',[(m['name'],m['size']) for m in media])
