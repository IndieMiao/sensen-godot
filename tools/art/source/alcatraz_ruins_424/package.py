"""Sign real-game ruin detail review; preserve the original scene and screenshots."""
from pathlib import Path
import ast,hashlib,json
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/alcatraz-ruins-424';DEST=ROOT/'docs/design/alcatraz-ruins-424-2026-11-06'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def main():
 a=json.loads((QA/'asset-validation.json').read_text());r=json.loads((QA/'render-validation.json').read_text());assert a['passed'] and r['passed']
 for name,entry in a['assets'].items():assert entry['sha256']==r['assets'][name]['sha256']==sha(ROOT/'assets/landmarks/alcatraz_island'/(name+'.glb'))
 for name,dst in [('review.gd','review.gd'),('suggested_placements.json','ruin_details_placements.json')]:
  assert sha(HERE/name)==sha(QA/'project'/dst)
  assert (QA/'render-validation.json').stat().st_mtime>=(HERE/name).stat().st_mtime,'stale/pending render'
 for log in ['render.log','reimport.log']:assert 'ERROR:' not in (QA/log).read_text(),log
 rows=[];bg='#F6F0E3';ink='#3C493B'
 def save(image,suffix,note):
  assert max(image.size)<=1600
  p=DEST/('SGODOT-424_ALC_RUINS_v1_'+suffix+'.png');meta=PngImagePlugin.PngInfo();meta.add_text('Author','赵云 / ZHAOYUN');meta.add_text('Description',note+' Godot Mobile Vulkan; no colour correction.')
  image.save(p,pnginfo=meta);rows.append(dict(name=p.name,path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size,mime='image/png',size=list(image.size)))
 src=Image.open(QA/'five_details_avatar.png').convert('RGB');out=Image.new('RGB',(1500,1080),bg);out.paste(src,(0,50));d=ImageDraw.Draw(out)
 d.text((24,10),'SGODOT-424 · 废墟细节五件 / 全部原尺寸 · 游戏人物约1.75 m',font=font(25),fill=ink)
 names={'alc_ruin_arch':'倾倒拱券残段','alc_ruin_rubble':'贴地砖石碎片','alc_ruin_vine':'挂墙藤蔓片','alc_ruin_flowers':'废墟野花丛','alc_ruin_plaque':'空白说明牌'}
 for row in r['gallery']:
  x,y=ast.literal_eval(row['label_at']);y+=50
  d.text((x,y),names[row['asset']],font=font(22),fill=ink,anchor='mt',stroke_width=2,stroke_fill=bg)
  d.text((x,y+30),f'{a["assets"][row["asset"]]["triangles"]} 面 / 1 surface',font=font(16),fill=ink,anchor='mt',stroke_width=1,stroke_fill=bg)
 x,y=ast.literal_eval(r['avatar_label_at']);d.text((x,y+50),'游戏人物',font=font(21),fill=ink,anchor='mt')
 d.text((24,1015),'浅暖石材、单层碎片与花草；无铁栏、牢门、铁丝网。说明牌无文字、无交互提示。',font=font(24),fill=ink)
 d.text((24,1050),'原白模灯光 / 单网格哑光顶点色 / 赵云 ZHAOYUN',font=font(20),fill=ink)
 save(out,'five_details_avatar','Five original-scale pieces next to game avatar; mounting vine presented upright for inspection.')
 for name,title in [('ruins_area_43','废墟区域 / 保留v6主体与旧树点位'),('ruins_details_close','拱券与藤蔓局部 / 保留原白模遮挡')]:
  src=Image.open(QA/(name+'.png')).convert('RGB');out=Image.new('RGB',(src.width,src.height+90),bg);out.paste(src,(0,0));d=ImageDraw.Draw(out)
  d.text((20,src.height+11),title+' · 检视相机俯角43° / 方位-35°',font=font(23),fill=ink)
  d.text((20,src.height+49),'ruins_000=(18.5,3.25,5)，仅追加细节；不是默认跟随镜头，也未移动原树 · 赵云 ZHAOYUN',font=font(19),fill=ink)
  save(out,name,'Local inspection camera at pitch43/yaw-35, original v6 ruin and trees retained; only detail objects added.')
 src=Image.open(QA/'native_route_43.png').convert('RGB');out=Image.new('RGB',(360,902),bg);out.paste(src,(0,0));d=ImageDraw.Draw(out)
 for i,line in enumerate(['沿路原生43° / 6.72m / 360×800','废墟在路线右侧，主体位置保持','完整废墟另看局部检视图','SGODOT-424 · 赵云 ZHAOYUN']):d.text((8,807+i*22),line,font=font(14),fill=ink)
 save(out,'native_route_43','Native route follow camera, unchanged; records actual limited view of the right-side ruin at default zoom.')
 report=dict(author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',assets=a,godot=r,stage=json.loads((QA/'stage.json').read_text()),source_blend_sha256=sha(HERE/'alcatraz_ruins_details.blend'),placements_sha256=sha(HERE/'suggested_placements.json'),images=rows)
 (DEST/'validation-v1.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');(DEST/'media-manifest-v1.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
 print('RUIN_PACKAGE',len(rows),'images',len(a['checks'])+len(r['checks']),'checks')
if __name__=='__main__':main()
