"""v1.1 supplement: two single trees and six-tree pond replacement; preserve v1 media."""
from pathlib import Path
import ast,hashlib,json,shutil
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/wild-422';DEST=ROOT/'docs/design/wild-props-422-2026-11-05'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def main():
 assets=json.loads((QA/'asset-validation.json').read_text());render=json.loads((QA/'render-validation.json').read_text());water=json.loads((QA/'water-preservation.json').read_text())
 assert assets['passed'] and render['passed'] and water['passed']
 for name in ['review.gd','scatter.gd','perimeter_trees.gd','density.json']:
  assert sha(HERE/name)==sha(QA/'project'/name)
  assert (QA/'render-validation.json').stat().st_mtime >= (HERE/name).stat().st_mtime, 'pending/stale render: '+name
 for name,asset in assets['assets'].items():
  assert asset['sha256']==render['assets'][name]['sha256']==sha(ROOT/'assets/farm/art'/(name+'.glb'))
  assert asset['triangles']==render['assets'][name]['triangles']
 assert all('ERROR:' not in (QA/log).read_text() for log in ['render.log','reimport.log'])
 rows=[];bg='#F6F0DF';ink='#37482B'
 def save(image,name,note):
  assert max(image.size)<=1600
  p=DEST/('SGODOT-422_WILD_v1.1_'+name+'.png');meta=PngImagePlugin.PngInfo();meta.add_text('Author','赵云 / ZHAOYUN');meta.add_text('Description',note+' Actual Godot Mobile Vulkan; original water/shore unchanged; no colour correction.')
  image.save(p,pnginfo=meta);rows.append(dict(name=p.name,path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size,mime='image/png',size=list(image.size)))
 source=Image.open(QA/'tree_comparison.png').convert('RGB')
 out=Image.new('RGB',(1500,1048),bg);out.paste(source,(0,54));d=ImageDraw.Draw(out)
 d.text((24,10),'SGODOT-422 · 单棵装饰树 / 可采集树林、硬木 · 原尺寸，同一塘内灯光',font=font(25),fill=ink)
 names={'wild_tree_pine':'装饰 · 单干松树','wild_tree_round':'装饰 · 单干圆冠树','spot_grove':'资源 · Timber 树林','hardwood_grove':'资源 · Hardwood 硬木'}
 for row in render['tree_gallery']:
  x,y=ast.literal_eval(row['label_at']);y+=54
  d.text((x,y),names[row['asset']],font=font(24),fill=ink,anchor='mt',stroke_width=2,stroke_fill='#EDF1D0')
  if not row['resource']:
   a=assets['assets'][row['asset']];d.text((x,y+34),f'{a["triangles"]} 面 / 1 surface / 高 {a["bounds"][1][1]:.3f} m',font=font(17),fill=ink,anchor='mt',stroke_width=1,stroke_fill='#EDF1D0')
 d.text((24,974),'单棵树形、浅色树干；装饰不带树桩、码木料或资源底座。原 12 件 GLB / .import 保持逐字节一致。',font=font(23),fill=ink)
 d.text((24,1014),'b1 / Godot Mobile Vulkan / RTX 2060 · 赵云 ZHAOYUN',font=font(21),fill=ink)
 save(out,'tree_comparison','Two new decorative trees versus unchanged Timber and Hardwood resources. All unit scale.')
 source=Image.open(QA/'gourd_default_43.png').convert('RGB');assert source.size==(360,800)
 out=Image.new('RGB',(360,924),bg);out.paste(source,(0,0));d=ImageDraw.Draw(out)
 lines=['SGODOT-422 v1.1 · gourd 开场 43°','360×800 / 六棵装饰树临时替换','水面、材质、岸石、相关贴图保持原样','原草地；原 12 件装饰保留','赵云 ZHAOYUN · Mobile Vulkan']
 for i,line in enumerate(lines):d.text((8,807+i*22),line,font=font(14),fill=ink)
 save(out,'gourd_default_43','Native 360x800 opening with six temporary decorative-tree replacements; no production tree integration.')
 source=Image.open(QA/'whole_pond_density.png').convert('RGB');out=Image.new('RGB',(1200,1290),bg);out.paste(source,(0,0));d=ImageDraw.Draw(out)
 d.text((22,1214),'全塘核对 · 3 棵松树 + 3 棵圆冠树替换原六棵装饰树 · 树冠避开启用槽位，根部留在可走区外',font=font(22),fill=ink)
 d.text((22,1252),'水与岸石源码、贴图逐文件一致 / 具体位置见 placements-gourd-v1.1.json · 赵云 ZHAOYUN',font=font(21),fill=ink)
 save(out,'whole_pond_trees','Wider view of the same exact placements; original water, shore, light and terrain retained.')
 shutil.copy2(QA/'placements.json',DEST/'placements-gourd-v1.1.json')
 shutil.copy2(QA/'water-preservation.json',DEST/'water-preservation-v1.1.json')
 report=dict(author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',assets=assets,godot=render,water_preservation=water,
  stage=json.loads((QA/'stage.json').read_text()),tree_source_sha256=sha(HERE/'wild_trees.blend'),original_source_sha256=sha(HERE/'wild_props.blend'),images=rows,
  placed_decoration_triangles=sum(assets['assets'][p['asset']]['triangles'] for p in render['scatter']['placements']),
  scope='Two new single decorative trees; previous 12 GLBs/imports preserved. Temporary tree replacements and slot avoidance in isolated review only. Water/shore materials, shaders, colours, textures and geometry unchanged.')
 (DEST/'validation-v1.1.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');(DEST/'media-manifest-v1.1.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
 print('WILD_TREE_PACKAGE',len(rows),'images;',len(assets['checks'])+len(render['checks']),'checks')
if __name__=='__main__':main()
