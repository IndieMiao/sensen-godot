"""Sign actual blockout/prop renders, at <=1600 px; never retouch the scene."""
from pathlib import Path
import ast,hashlib,json,shutil
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/alcatraz-props-424';DEST=ROOT/'docs/design/alcatraz-props-424-2026-11-06'
NAMES={'alc_bench':'长椅','alc_lamp':'公园路灯','alc_rail_straight':'2m 石栏直段','alc_rail_corner':'石栏转角','alc_curb':'2m 石沿','alc_tree_a':'风吹柏树','alc_tree_b':'圆冠树','alc_flowerbed':'花坛','alc_bin':'垃圾桶','alc_sign':'空白指示牌'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def main():
 a=json.loads((QA/'asset-validation.json').read_text());r=json.loads((QA/'render-validation.json').read_text());assert a['passed'] and r['passed']
 for name,entry in a['assets'].items():assert entry['sha256']==r['assets'][name]['sha256']==sha(ROOT/'assets/landmarks/alcatraz_island'/(name+'.glb'))
 assert sha(HERE/'review.gd')==sha(QA/'project/review.gd') and (QA/'render-validation.json').stat().st_mtime>=(HERE/'review.gd').stat().st_mtime
 for log in ['reimport.log','render.log']:assert 'ERROR:' not in (QA/log).read_text(),log
 rows=[];bg='#F6F0E3';ink='#3C493B'
 def save(image,suffix,note):
  assert max(image.size)<=1600
  p=DEST/('SGODOT-424_ALC_PROPS_v1_'+suffix+'.png');meta=PngImagePlugin.PngInfo();meta.add_text('Author','赵云 / ZHAOYUN');meta.add_text('Description',note+' Godot Mobile Vulkan, no colour correction.')
  image.save(p,pnginfo=meta);rows.append(dict(name=p.name,path=str(p.relative_to(ROOT)),sha256=sha(p),bytes=p.stat().st_size,mime='image/png',size=list(image.size)))
 src=Image.open(QA/'all_props_avatar.png').convert('RGB');out=Image.new('RGB',(1500,1590),bg);out.paste(src,(0,48));d=ImageDraw.Draw(out)
 d.text((24,10),'SGODOT-424 · 重复小件 10 种 / 全部 1.0 倍 · 真人比例基线 1.75 m',font=font(24),fill=ink)
 for row in r['gallery']:
  x,y=ast.literal_eval(row['label_at']);y+=48
  d.text((x,y),NAMES[row['asset']],font=font(22),fill=ink,anchor='mt',stroke_width=2,stroke_fill=bg)
  d.text((x,y+29),f'{a["assets"][row["asset"]]["triangles"]} 面 / 1 surface',font=font(16),fill=ink,anchor='mt',stroke_width=1,stroke_fill=bg)
 x,y=ast.literal_eval(r['gallery_avatar']['label_at']);d.text((x,y+48),'游戏人物 · 约 1.75 m',font=font(20),fill=ink,anchor='mt',stroke_width=2,stroke_fill=bg)
 d.text((24,1510),'长椅座高 0.45 m / 长 1.50 m · 路灯 3.50 m · 石栏 1.00 m · 石沿 0.25 m · 树 6.42 / 6.28 m',font=font(22),fill=ink)
 d.text((24,1550),'同白模灯光；模型底部安装原点，非整岛烘焙 / 赵云 ZHAOYUN',font=font(21),fill=ink)
 save(out,'all_props_avatar','All ten final prototypes at 1.0 scale alongside the existing game avatar; flat inspection platform, original blockout lights.')
 src=Image.open(QA/'opening_43.png').convert('RGB');assert src.size==(360,800)
 out=Image.new('RGB',(360,902),bg);out.paste(src,(0,0));d=ImageDraw.Draw(out)
 for i,line in enumerate(['SGODOT-424 · 原白模开场 43°','6.72 m / 360×800 / 人物原比例','34df9c0b 原点位；只替换10种重复件','赵云 ZHAOYUN · Mobile Vulkan']):d.text((8,807+i*22),line,font=font(14),fill=ink)
 save(out,'opening_43','Unchanged Marco Polo 34df9c0b blockout layout/camera/nav; replacement GLBs only. Structural set remains blockout.')
 src=Image.open(QA/'rail_stair_detail.png').convert('RGB');out=Image.new('RGB',(1200,990),bg);out.paste(src,(0,0));d=ImageDraw.Draw(out)
 d.text((22,913),'白模楼梯段接缝核查 · 标准2m模块按原 basis_columns 装配，立柱保持竖直',font=font(23),fill=ink)
 d.text((22,950),'原layout的10处0.125m过渡高差另列报告，待场景方修点位；无暗改摆位 · 赵云 ZHAOYUN',font=font(20),fill=ink)
 save(out,'rail_stair_detail','Unchanged sloped-blockout transforms; this is an integration audit, not a claim that old layout transitions are resolved.')
 report=dict(author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',assets=a,godot=r,stage=json.loads((QA/'stage.json').read_text()),source_blend_sha256=sha(HERE/'alcatraz_props.blend'),images=rows)
 (DEST/'validation-v1.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');(DEST/'media-manifest-v1.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
 (HERE/'seam-audit.json').write_text(json.dumps({'layout_commit':'34df9c0b','exact_join_pairs':a['exact_joins'],'existing_height_transitions':a['existing_height_transitions'],'note':'These gaps come from the reference placements, unchanged by the final 2m modules.'},ensure_ascii=False,indent=2)+'\n')
 print('ALC_PACKAGE',len(rows),'images',len(a['checks'])+len(r['checks']),'checks')
if __name__=='__main__':main()
