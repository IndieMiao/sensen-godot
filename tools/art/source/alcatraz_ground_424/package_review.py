"""Caption actual Godot frames without repainting or rescaling the portrait views."""
from pathlib import Path
import shutil
from PIL import Image, ImageFont, ImageDraw
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
OUT=ROOT/'output/alcatraz-ground-424';DOC=ROOT/'docs/design/alcatraz-ground-424'
FONT='/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc'
def font(n):return ImageFont.truetype(FONT,n)
def main():
 DOC.mkdir(parents=True,exist_ok=True)
 for name,label in [('opening','开场'),('mid_hill','半山'),('summit','山顶')]:
  canvas=Image.new('RGB',(756,910),'#f3f1e8');draw=ImageDraw.Draw(canvas)
  for x,suffix,title in [(12,'before','原顶点色'),(384,'after','可选细节材质')]:
   im=Image.open(OUT/'captures'/f'{name}-{suffix}.png').convert('RGB');assert im.size==(360,800)
   canvas.paste(im,(x,60));draw.text((x,16),label+' / '+title,font=font(21),fill='#354138')
   shutil.copy2(OUT/'captures'/f'{name}-{suffix}.png',DOC/f'{name}-{suffix}-360x800.png')
  draw.text((12,875),'刘备 · #792 bf0c31b1 · 原镜头 6.72 m / 原光照 / Vulkan Mobile',font=font(17),fill='#354138')
  canvas.save(DOC/f'{name}-comparison.png')
 for name,label in [('whole_island','整岛 · 可选草坡 / 铺石 / 木纹'),('grass_paving_detail','草坡与铺石近景'),('dock_grain_detail','码头木纹近景 · 板缝沿用原模型')]:
  im=Image.open(OUT/'captures'/f'{name}-after.png').convert('RGB')
  canvas=Image.new('RGB',(im.width,im.height+95),'#f3f1e8');canvas.paste(im,(0,50));draw=ImageDraw.Draw(canvas)
  draw.text((16,12),label,font=font(23),fill='#354138')
  draw.text((16,im.height+61),'刘备 · 原始渲染像素；仅附加标题和说明',font=font(18),fill='#354138');canvas.save(DOC/f'{name}.png')
 for src,dest in [(OUT/'captures/render-validation.json','render-validation.json'),(OUT/'source-validation.json','source-validation.json')]:shutil.copy2(src,DOC/dest)
 android=OUT/'android'
 if (android/'smoke.json').exists():
  shutil.copy2(android/'smoke.json',DOC/'android-smoke.json')
  for name in ['dock-opening','mid_hill','summit']:shutil.copy2(android/(name+'.png'),DOC/('android-'+name+'.png'))
 print('Three native portrait pairs and three detail/whole-island views packaged.')
if __name__=='__main__':main()
