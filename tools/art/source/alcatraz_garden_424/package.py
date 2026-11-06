"""Signed review sheets from native Godot renders; no colour or scene retouching."""
from pathlib import Path
import ast,hashlib,json,shutil
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/alcatraz-garden-424';DEST=ROOT/'docs/design/alcatraz-garden-424-2026-11-06'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def main():
 a=json.loads((QA/'asset-validation.json').read_text());r=json.loads((QA/'render-validation.json').read_text());points=json.loads((HERE/'suggested_placements.json').read_text());assert a['passed'] and r['passed']
 for name,asset in a['assets'].items():assert asset['sha256']==r['assets'][name]['sha256']==sha(ROOT/'assets/landmarks/alcatraz_island'/(name+'.glb'))
 for name,dst in [('review.gd','review.gd'),('suggested_placements.json','garden_placements.json')]:
  assert sha(HERE/name)==sha(QA/'project'/dst)
  assert (QA/'render-validation.json').stat().st_mtime>=(HERE/name).stat().st_mtime,'pending/stale render'
 for log in ['render.log','reimport.log']:assert 'ERROR:' not in (QA/log).read_text(),log
 rows=[];bg='#F6F0E3';ink='#3C493B'
 def save(image,suffix,note):
  assert max(image.size)<=1600
  p=DEST/('SGODOT-424_ALC_GARDEN_v1_'+suffix+'.png');meta=PngImagePlugin.PngInfo();meta.add_text('Author','赵云 / ZHAOYUN');meta.add_text('Description',note+' Godot Mobile Vulkan. No colour correction.')
  image.save(p,pnginfo=meta);rows.append(dict(name=p.name,path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size,mime='image/png',size=list(image.size)))
 src=Image.open(QA/'five_props_avatar.png').convert('RGB');out=Image.new('RGB',(1500,980),bg);out.paste(src,(0,50));d=ImageDraw.Draw(out)
 d.text((24,10),'SGODOT-424 · 台地花卉、绿篱与盆栽 / 全部原尺寸 · 人物约1.75 m',font=font(25),fill=ink)
 names={'alc_flowers_poppy':'橙色加州罂粟','alc_flowers_lavender':'紫色薰衣草','alc_flowers_daisy':'白色雏菊','alc_hedge':'1m 直绿篱','alc_planter':'台地陶盆绿植'}
 for row in r['gallery']:
  x,y=ast.literal_eval(row['label_at']);y+=50
  d.text((x,y),names[row['asset']],font=font(21),fill=ink,anchor='mt',stroke_width=2,stroke_fill=bg)
  d.text((x,y+30),f'{a["assets"][row["asset"]]["triangles"]} 面 / 1 surface',font=font(16),fill=ink,anchor='mt',stroke_width=1,stroke_fill=bg)
 x,y=ast.literal_eval(r['avatar_label_at']);d.text((x,y+50),'游戏人物',font=font(21),fill=ink,anchor='mt')
 d.text((24,919),'三种花按色块轮换，低绿篱留缺口；盆栽放台地西侧端头 · 顶点色 / 哑光 / 单网格',font=font(23),fill=ink)
 d.text((24,951),'Blender / Godot 经 gs66-render.lock · 赵云 ZHAOYUN',font=font(19),fill=ink)
 save(out,'five_props_avatar','Five unit-scale final prototypes in original island light, with the actual game avatar.')
 out=Image.new('RGB',(1080,914),bg);d=ImageDraw.Draw(out)
 for i in range(3):
  src=Image.open(QA/f'terrace_{i+1}_43.png').convert('RGB');assert src.size==(360,800);out.paste(src,(i*360,50));d.text((i*360+12,12),f'台地 {i+1} · 43° / 6.72 m',font=font(22),fill=ink)
 d.text((18,862),'三个台地的原生默认镜头 · 色块看点沿窄花带错开，步道与原栏杆保持 / 赵云 ZHAOYUN',font=font(20),fill=ink)
 d.text((18,891),'背景为 b16c3198 v6 白模；本次仅追加五种花园件，未冒充整岛最终上色',font=font(17),fill=ink)
 save(out,'three_terraces_43','Three unretouched 360x800 default follow screenshots, same camera/light and actual player scale.')
 src=Image.open(QA/'terraces_overview.png').convert('RGB');out=Image.new('RGB',(1200,1490),bg);out.paste(src,(0,0));d=ImageDraw.Draw(out)
 d.text((22,1413),f'15个台地看点 / {len(points["instances"])}个建议点位 / 最大片段间距6.5m / 原layout与导航保持',font=font(23),fill=ink)
 d.text((22,1452),'全景只作花园布局核对；原建筑、树和旧小件仍为v6白模/协作资产 · 赵云 ZHAOYUN',font=font(20),fill=ink)
 save(out,'terraces_overview','Wider placement overview, all new garden pieces shown; unchanged v6 base scene.')
 src=Image.open(QA/'opening_43.png').convert('RGB');out=Image.new('RGB',(360,878),bg);out.paste(src,(0,0));d=ImageDraw.Draw(out)
 for i,line in enumerate(['原v6开场 / 360×800 / 43°','不移动既有高件，不改水面、主体或路径','SGODOT-424 · 赵云 ZHAOYUN']):d.text((8,807+i*22),line,font=font(14),fill=ink)
 save(out,'opening_43','Original v6 opening for integration context; garden views are the separate three-terrace sheet.')
 report=dict(author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',assets=a,godot=r,stage=json.loads((QA/'stage.json').read_text()),source_blend_sha256=sha(HERE/'alcatraz_garden.blend'),placements_sha256=sha(HERE/'suggested_placements.json'),images=rows)
 (DEST/'validation-v1.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');(DEST/'media-manifest-v1.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
 print('GARDEN_PACKAGE',len(rows),'images;',len(a['checks'])+len(r['checks']),'checks')
if __name__=='__main__':main()
