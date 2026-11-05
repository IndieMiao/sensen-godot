"""Steam-only delivery: protect accepted art/animation and validate actual pixels."""
from pathlib import Path
import hashlib,json,re,subprocess
import numpy as np
from PIL import Image,ImageDraw,ImageFont
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
OUT=ROOT/'output/cookpot-419';RENDERS=OUT/'renders'
DOC=ROOT/'docs/design/cooking-pot-wait-419-2026-11-05/v1.2';DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-419_cooking_pot_v1.2_';BASE='a0e56f56'
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def font(size):return ImageFont.truetype(FONT,size)
def digest(data):return hashlib.sha256(data).hexdigest()
def base_file(p):return subprocess.check_output(['git','show',BASE+':'+p],cwd=ROOT)
protected={}
for path in (ROOT/'assets/props/cooking_pot_wait').iterdir():
    if path.suffix=='.res' or path.name in ['soup_matte.tres','resource_uids.json']:
        rel=str(path.relative_to(ROOT));assert path.read_bytes()==base_file(rel)
        protected[rel]=digest(path.read_bytes())
glb='assets/props/stove_pot/stove_pot.glb'
assert (ROOT/glb).read_bytes()==base_file(glb);protected[glb]=digest((ROOT/glb).read_bytes())
scene='assets/props/cooking_pot_wait/cooking_pot_wait.tscn'
def sections(text):return {s.splitlines()[0]:s.strip() for s in re.split(r'(?=^\[)',text,flags=re.M) if s.strip()}
old=sections(base_file(scene).decode());new=sections((ROOT/scene).read_text());unchanged_sections=[]
for name,text in old.items():
    if name.startswith('[sub_resource') and any('type="'+s+'"' in name for s in ['Gradient','GradientTexture1D','Curve','CurveTexture','ParticleProcessMaterial','QuadMesh']):continue
    if name.startswith('[node name="Steam"'):continue
    assert new[name]==text,name
    unchanged_sections.append(name)
assert set(new)-set(old)=={'[ext_resource type="Script" path="res://assets/props/cooking_pot_wait/steam_lid_clearance.gd" id="8_steam_mask"]'}
for name,title in [('closed','合盖 · 0.12 s'),('lifted','顶起 · 0.88 s'),('settled','落回 · 1.28 s')]:
    im=Image.open(RENDERS/(PREFIX+name+'.png')).convert('RGB');d=ImageDraw.Draw(im)
    d.text((22,18),'SGODOT-419 / v1.2 / '+title,font=font(22),fill='#344C40')
    d.text((22,678),'黄忠 · 暖白蒸汽 · 盖沿以内透明 · 模型及动作不变',font=font(17),fill='#344C40')
    im.save(DOC/(PREFIX+name+'.png'))
im=Image.new('RGB',(840,820),'#E6DDCB')
raw=Image.open(RENDERS/(PREFIX+'lifted.png')).convert('RGB')
crop=raw.crop((290,70,520,330)).resize((644,728),Image.Resampling.NEAREST)
im.paste(crop,(98,52));d=ImageDraw.Draw(im)
d.text((20,13),'黄忠 · 盖子正上方 / 原渲染最近邻放大 2.8×',font=font(22),fill='#344C40')
d.text((20,786),'#FFF8F0 · 单粒 alpha ≤ 0.35 · 总升高 19.8 cm',font=font(20),fill='#344C40')
im.save(DOC/(PREFIX+'steam_detail.png'))
pixels=[]
for pitch,name,y in re.findall(r'STEAM_MASK (\d+) (\w+) lid_top_y=([\d.]+)',(OUT/'steam-render-v12.log').read_text()):
    base=RENDERS/f'steam_v12_masks/{pitch}_{name}'
    on=np.asarray(Image.open(str(base)+'_on.png').convert('RGB')).astype('int16')
    off=np.asarray(Image.open(str(base)+'_off.png').convert('RGB')).astype('int16')
    delta=np.abs(on-off).max(2);cut=int(float(y))
    row={'pitch_degrees':int(pitch),'pose':name,'lid_top_y':float(y),'steam_pixels_above':int(np.count_nonzero(delta[:cut])),'steam_pixels_below':int(np.count_nonzero(delta[cut:])),'max_rgb_difference_below':int(delta[cut:].max()),'max_rgb_difference_above':int(delta[:cut].max())}
    assert row['steam_pixels_above']>0 and row['steam_pixels_below']==0,row
    pixels.append(row)
assert len(pixels)==6
validation=json.loads((OUT/'validation.json').read_text())
validation.update(author='黄忠',virtual_user_id='5281cd25-6a49-4df8-9802-f3e534956e80',base=BASE,unchanged_sha256=protected,unchanged_scene_sections=unchanged_sections,pixel_checks=pixels)
(DOC/(PREFIX+'validation.json')).write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
manifest=[]
for path in sorted(DOC.glob(PREFIX+'*')):
    row={'file':path.name,'bytes':path.stat().st_size,'sha256':digest(path.read_bytes())}
    if path.suffix=='.png':row['size']=list(Image.open(path).size)
    manifest.append(row)
(DOC/'media-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('Verified',len(unchanged_sections),'unchanged scene sections;',len(pixels),'RGB cases;',len(manifest),'delivery files')
