"""Caption unmodified native frames. No repainting of sea, foam or bridge."""
from pathlib import Path
import shutil
from PIL import Image,ImageFont,ImageDraw
S=Path(__file__).resolve().parent;R=S.parents[3];O=R/'output/alcatraz-foam-424';D=R/'docs/design/alcatraz-foam-424';font='/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc'
def f(n):return ImageFont.truetype(font,n)
def caption(raw,dest,title,footer):
 im=Image.open(O/'captures'/raw).convert('RGB');can=Image.new('RGB',(im.width,im.height+130),'#f3f1e8');can.paste(im,(0,65));d=ImageDraw.Draw(can);d.text((18,14),title,font=f(24),fill='#354138');d.text((18,im.height+86),footer,font=f(18),fill='#354138');can.save(D/dest)
caption('01_six_assets.png','six-assets.png','刘备 · SGODOT-424 · 独立浪花四件 / 浮标 / 浮木 / 1.75 m 人物','上排：strip_a 24面 / strip_b 32面 / strip_c 24面；下排：ring 64面 / buoy 184面 / driftwood 130面。')
caption('04_shore_closeup.png','shore-closeup.png','刘备 · 岸边近景 · 独立静态浪花 / 水边小件','地形与海面沿用 #792 d7b57574；岩石 #801 v3、码头 #821 为隔离验图背景。')
caption('06_rock_contacts.png','rock-contacts.png','刘备 · 环形浪花贴合三种岩石 / 岸脚柔边','单独透明片，Y=-0.132（高于原海面1.8 cm）；无水面材质改动。')
caption('07_whole_island.png','whole-island.png','刘备 · 整岛岸线浪花 / Godot Mobile','按实际海平面截线布置；107实例 / 6批次；左上看桥留白带已避让。')
shutil.copy2(O/'captures/03_dock_opening.png',D/'dock-opening-360x800.png')
can=Image.new('RGB',(756,900),'#f3f1e8');d=ImageDraw.Draw(can)
for x,n,label in [(12,'02_opening_before','添加前 / 宿主与已交码头件'),(384,'03_dock_opening','添加后 / 独立浪花与水边小件')]:
 im=Image.open(O/'captures'/f'{n}.png').convert('RGB');assert im.size==(360,800);can.paste(im,(x,55));d.text((x,18),label,font=f(20),fill='#354138')
d.text((12,867),'刘备 · 原开场同镜头 / 同光照；桥与城市带 RGB 最大差 0/255',font=f(18),fill='#354138');can.save(D/'opening-comparison.png')
for n in ['render-validation.json']:shutil.copy2(O/'captures'/n,D/n)
shutil.copy2(O/'import-validation.json',D/'import-validation.json')
print('ALC_FOAM_REVIEW_PACKAGED')
