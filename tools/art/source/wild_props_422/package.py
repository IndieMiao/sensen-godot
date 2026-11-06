"""Sign native Godot screenshots, preserving colour and unit-scale comparison."""
from pathlib import Path
import ast,hashlib,json,shutil
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/wild-422';DEST=ROOT/'docs/design/wild-props-422-2026-11-05'
NAMES={'spot_grove':'资源 · 树林','spot_rock_pile':'资源 · 石堆','flax_patch':'资源 · 亚麻','reed_bank':'资源 · 芦苇滩',
 'wild_flower_white':'白雏菊','wild_flower_yellow':'黄野花','wild_flower_lilac':'淡紫野花','wild_clover':'苜蓿叶团',
 'wild_pebbles_a':'贴地散石 A','wild_pebbles_b':'贴地散石 B','wild_mushrooms':'蘑菇丛','wild_log_moss':'苔藓倒木','wild_fern':'蕨类',
 'wild_bush_dark':'深绿圆灌木','wild_bush_olive':'黄绿圆灌木','wild_cattail_water':'水中香蒲'}
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 assets=json.loads((QA/'asset-validation.json').read_text());render=json.loads((QA/'render-validation.json').read_text())
 assert assets['passed'] and render['passed']
 # A renderer may still be queued on the shared lock: never package its previous report.
 for name in ['review.gd','scatter.gd','density.json']:
  assert sha(HERE/name)==sha(QA/'project'/name), 'staged render input differs: '+name
  assert (QA/'render-validation.json').stat().st_mtime >= (HERE/name).stat().st_mtime, 'render still pending/stale: '+name
 for name,asset in assets['assets'].items():
  assert asset['sha256']==render['assets'][name]['sha256']==sha(ROOT/'assets/farm/art'/(name+'.glb'))
  assert asset['triangles']==render['assets'][name]['triangles']
 assert all('ERROR:' not in (QA/log).read_text() for log in ['render.log','reimport.log'])
 rows=[];bg='#F6F0DF';ink='#37482B'
 def save(image,name,note):
  assert max(image.size)<=1600
  p=DEST/('SGODOT-422_WILD_v1_'+name+'.png');meta=PngImagePlugin.PngInfo();meta.add_text('Author','赵云 / ZHAOYUN');meta.add_text('Description',note+' Actual Godot Mobile Vulkan; no colour correction.')
  image.save(p,pnginfo=meta)
  rows.append(dict(name=p.name,path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size,mime='image/png',size=list(image.size)))
 source=Image.open(QA/'all_props_resources.png').convert('RGB')
 out=Image.new('RGB',(source.width,source.height+134),bg);out.paste(source,(0,54));d=ImageDraw.Draw(out)
 d.text((24,10),'SGODOT-422 · 野外装饰 12 件 / 既有资源 4 种 · 全部原尺寸，同一塘内灯光',font=font(25),fill=ink)
 for row in render['gallery']:
  at=ast.literal_eval(row['label_at']) if isinstance(row['label_at'],str) else row['label_at'];x,y=at[0],at[1]+54
  d.text((x,y),NAMES[row['asset']],font=font(22 if row['resource'] else 20),fill=ink,anchor='mt',stroke_width=2,stroke_fill='#EFF0C8')
  if not row['resource']:
   n=assets['assets'][row['asset']]['triangles'];d.text((x,y+28),f'{n} 面 / 1 surface',font=font(15),fill=ink,anchor='mt',stroke_width=1,stroke_fill='#EFF0C8')
 d.text((24,source.height+67),'装饰无蓝花、无采集底座；散石高 0.090 / 0.108 m；香蒲两根细茎、无泥底（此图干摆核轮廓，场景里只放水中）',font=font(21),fill=ink)
 d.text((24,source.height+103),'b1 / Godot Mobile Vulkan / RTX 2060 · 赵云 ZHAOYUN',font=font(19),fill=ink)
 save(out,'all_props_resources','Unit-scale comparison. Cattail shown on the comparison staging ground only; actual scenery places it exclusively in water.')
 source=Image.open(QA/'gourd_default_43.png').convert('RGB');assert source.size==(360,800)
 out=Image.new('RGB',(360,902),bg);out.paste(source,(0,0));d=ImageDraw.Draw(out)
 for i,line in enumerate(['SGODOT-422 · gourd 开场 43° / 360×800','装饰预览；地表仍为 b1 原草地','103 个装饰 / 3 组倒木 / 槽位净空 ≥1.5 m','赵云 ZHAOYUN · Mobile Vulkan']):d.text((9,807+i*22),line,font=font(14),fill=ink)
 save(out,'gourd_default_43','Unmodified 360x800 native opening image above the signature footer. Original b1 terrain; Liu Bei ground pass not integrated.')
 source=Image.open(QA/'whole_pond_density.png').convert('RGB')
 out=Image.new('RGB',(1200,1290),bg);out.paste(source,(0,0));d=ImageDraw.Draw(out)
 d.text((22,1214),'全塘密度核对（放宽机位）· 3 组倒木 / 蘑菇 / 蕨类 · 水中香蒲 7 丛 · 中央保持开阔',font=font(23),fill=ink)
 d.text((22,1252),'原生草地与边界；撒点坐标、净空和默认屏幕范围另见 placements-gourd-v1.json · 赵云 ZHAOYUN',font=font(20),fill=ink)
 save(out,'whole_pond_density','Wider camera audit of the same exact placement set, same native pond lighting.')
 shutil.copy2(QA/'placements.json',DEST/'placements-gourd-v1.json')
 report=dict(author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',assets=assets,godot=render,
  stage=json.loads((QA/'stage.json').read_text()),source_blend_sha256=sha(HERE/'wild_props.blend'),images=rows,
  scope='Art assets and placement proposal only. Existing ground is retained; no production shader, navigation, collision or scatter integration committed.',
  lock='All Blender / Godot execution serialized with flock /home/zhangshaoji/gs66-render.lock; ADB port 5099; every process exits after work.')
 (DEST/'validation-v1.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 (DEST/'media-manifest-v1.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
 print('WILD_PACKAGE',len(rows),'images;',len(assets['checks'])+len(render['checks']),'checks')
if __name__=='__main__':main()
