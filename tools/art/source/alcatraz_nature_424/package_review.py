"""Add captions OUTSIDE unchanged Godot frames; no pixel repainting."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import shutil
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/alcatraz-nature-424';DOC=ROOT/'docs/design/alcatraz-nature-424'
font='/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc'
def f(size):return ImageFont.truetype(font,size)
def labeled(raw,dest,title,footer):
 im=Image.open(raw).convert('RGB');canvas=Image.new('RGB',(im.width,im.height+138),'#f3f1e8');canvas.paste(im,(0,70));d=ImageDraw.Draw(canvas)
 d.text((22,14),title,font=f(25),fill='#354138');d.text((22,im.height+86),footer,font=f(19),fill='#4d564d');canvas.save(DOC/dest)
im=Image.open(OUT/'captures/01_scale_lineup.png').convert('RGB');canvas=Image.new('RGB',(1500,820),'#f3f1e8');canvas.paste(im,(0,70));d=ImageDraw.Draw(canvas)
d.text((25,16),'刘备 · SGODOT-424  |  岸石 / 灌木 / 草丛  |  同比例 Godot Mobile 实渲',font=f(28),fill='#354138')
labels=[(159,'alc_rock_a','0.95 × 0.70 × 0.84 m'),(348,'alc_rock_b','1.85 × 1.18 × 1.42 m'),(613,'alc_rock_c','2.80 × 2.08 × 2.24 m'),(882,'alc_shrub','0.91 × 0.62 × 0.77 m'),(1032,'alc_shrub_b','1.17 × 0.82 × 1.02 m'),(1182,'alc_grass_tuft','0.49 × 0.42 × 0.48 m'),(1315,'人物','高度 1.75 m')]
for x,name,size in labels:
 d.text((x,735),name,font=f(18),fill='#354138',anchor='mt');d.text((x,766),size,font=f(12),fill='#4d564d',anchor='mt')
canvas.save(DOC/'scale-lineup.png')
for raw,dest,title,footer in [
 ('04_blockout_shore','blockout-shore.png','刘备 · 岸边岩石与低灌木 / 放入 #792 白模','主体 b16c3198；六件正式原型替换 114 个刘备占位；海面、建筑和地形沿用白模。'),
 ('05_blockout_terraces','blockout-terraces.png','刘备 · 台地低灌木与草丛 / Godot Mobile','点位已避让原导航面；最终山坡改形后由主体重新贴地。'),
 ('06_whole_island','whole-island.png','刘备 · 114 个替换实例 / 白模整岛查看','当前白模不是最终整景美术；本次原型共 968 三角面，放置共 14,176 三角面。'),
 ('02_rock_detail','rock-detail.png','刘备 · v3 三种略冷灰褐岸石 / 切面与凹裂带','每件 196 三角面 / 1 surface；共享顶点色哑光材质。'),
 ('03_foliage_detail','foliage-detail.png','刘备 · 深绿、偏黄绿灌木与六片折叶草丛','灌木 140 / 180 三角面，草丛 60 三角面含背面；无透明贴图。')]:
 labeled(OUT/'captures'/f'{raw}.png',dest,title,footer)
shutil.copy2(OUT/'captures/07_default_opening.png',DOC/'default-opening-360x800.png')
shutil.copy2(OUT/'captures/render-validation.json',DOC/'render-validation.json')
shutil.copy2(OUT/'import-validation.json',DOC/'import-validation.json')
if (OUT/'android/smoke.json').exists():
 shutil.copy2(OUT/'android/smoke.json',DOC/'android-validation.json')
 frames=[Image.open(OUT/'android'/f'{n}.png').convert('RGB') for n in ['opening','touch','whole']]
 canvas=Image.new('RGB',(1080,918),'#f3f1e8');d=ImageDraw.Draw(canvas)
 d.text((18,12),'Android 模拟器 · 360 × 800 · Vulkan Mobile / SwiftShader',font=f(25),fill='#354138')
 for i,(im,label) in enumerate(zip(frames,['开场 / 完整角色','真实触控后','整岛检查'])):
  assert im.size==(360,800);canvas.paste(im,(i*360,60));d.text((i*360+15,876),label,font=f(22),fill='#354138')
 canvas.save(DOC/'android-smoke.png')
print('ALC_REVIEW_PACKAGED')
