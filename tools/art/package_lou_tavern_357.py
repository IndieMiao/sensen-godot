#!/usr/bin/env python3
"""Signed Lou and native card-room wall comparisons for SGODOT-357."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from package_npc_batch3 import sheet,font

ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'docs/design/npc-parts-batch3-2026-10-29/lou-tavern'
parser=argparse.ArgumentParser();parser.add_argument('--runtime-root',type=Path,required=True)
args=parser.parse_args();runtime=args.runtime_root.resolve();source=runtime/'output/npc-batch3'
DEST.mkdir(parents=True,exist_ok=True);(DEST/'.gdignore').touch()
media=[]
def read(path):return Image.open(path).convert('RGB')
def save(name,picture,title,note):
    image=Image.new('RGB',(picture.width,picture.height+116),'#f5f6f3');image.paste(picture,(0,72))
    draw=ImageDraw.Draw(image);draw.text((20,10),'【赵云】SGODOT-357 · LOU v1',font=font(24),fill='#243b43')
    draw.text((20,40),title,font=font(20),fill='#243b43');draw.text((20,image.height-34),note,font=font(16),fill='#526970')
    path=DEST/('SGODOT-357_LOU_v1_'+name+'.png');image.save(path,optimize=True)
    media.append({'name':path.name,'path':str(path.relative_to(ROOT)),'size':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
save('01_lou_sigrid',sheet([(label,read(source/'lou-portraits'/(key+'_card.jpg'))) for label,key in
     [('Lou · 占位 A','lou_now'),('Lou · 酒红马甲 / 领结','lou_new'),('Sigrid · 原藏青正装','sigrid')]],300,3),
     '居民卡舞台 · Lou 改前 / 改后 / Sigrid','cloth1 衬衫底件，酒红马甲、黑领结、深色长裤；头发、鞋和 Sigrid 保持原件。')
save('02_cloth_closeups',sheet([(label+' · '+text,read(source/'lou-closeups'/('lou_cloth_'+state+'_'+side+'.png')))
     for side,label in [('front','正面'),('back','背面')] for state,text in [('before','底件'),('after','新件')]],460,2),
     '衣服正背近景 · 同镜头 / 同光照','一件 cloth1_npc_lou，2,811 面；一个 mesh / surface；原 FBX 层级、骨架和节点变换保留。')
motion=json.loads((source/'lou-motion/motion-validation.json').read_text())
save('03_motion',sheet([(e['motion']+' %.2fs / %d°'%(e['time'],round(e['yaw']*180/np.pi)),read(source/'lou-motion'/e['name']))
     for e in motion['captures']],250,4),'站立 / 行走 / 侧背面 · 马甲与长裤',
     '使用原动画，原 59 个绑定矩阵；长裤按同名骨骼映射，检查领结、衣摆和裤腿变形。')
wall=source/'tavern-captures'
save('04_wall_opening',sheet([('改前',read(wall/'opening-before.png')),('改后',read(wall/'opening-after.png'))],540,2),
     '原生牌室开场镜头 · 后墙接触 AO 修正',
     'P0Outpost 原生开场与隐藏逻辑；360×800 构图，720×1600 捕获；两图 NPC / 灯光 / 材质参数相同。')
save('05_wall_closeup',sheet([('改前 · 原托架处竖向暗带',read(wall/'bracket-before.png')),
     ('改后 · 木色与板缝连续',read(wall/'bracket-after.png'))],800,2),
     '原托架位置近景 · 仅修图集 297 个像素',
     '图集 x=815–840、y=1027–1048；其他部件使用像素不变，所有 GLB 几何与 UV 不变，无重新导出。')
delta={}
for view in ['opening','bracket']:
    before=np.asarray(read(wall/(view+'-before.png')));after=np.asarray(read(wall/(view+'-after.png')))
    mask=np.any(before!=after,axis=2);y,x=np.where(mask)
    assert len(x)>0
    delta[view]={'changed_pixels':int(mask.sum()),'rectangle_xyxy':[int(x.min()),int(y.min()),int(x.max()+1),int(y.max()+1)]}
wall_report=json.loads((wall/'render-validation.json').read_text())
shots={c['name']:c for c in wall_report['captures']}
for view in ['opening','bracket']:
    assert shots[view+'-before']['camera_transform']==shots[view+'-after']['camera_transform']
    assert shots[view+'-before']['camera_size']==shots[view+'-after']['camera_size']
assert wall_report['renderer']=='mobile'
for src,name in [(source/'lou-validation.json','godot-validation.json'),
                 (source/'lou-motion/motion-validation.json','motion-validation.json'),
                 (source/'lou-closeups/render-validation.json','closeup-validation.json'),
                 (wall/'render-validation.json','wall-render-validation.json'),
                 (source/'tavern-baseline.json','wall-imported-baseline.json'),
                 (ROOT/'output/npc-batch3/tavern/uv-ownership.json','wall-uv-ownership.json'),
                 (ROOT/'tools/art/source/npc_batch3/tavern-ao-357-validation.json','wall-pixel-validation.json'),
                 (ROOT/'tools/art/source/npc_batch3/lou-geometry-validation.json','geometry-validation.json'),
                 (source/'looks-phase3.json','looks-phase3.json'),
                 (runtime/'reports/report_3/results.xml','tests.xml')]:
    shutil.copy2(src,DEST/name)
(DEST/'wall-render-delta.json').write_text(json.dumps(delta,indent=2)+'\n')
(DEST/'media-manifest.json').write_text(json.dumps(media,indent=2)+'\n')
print('LOU_TAVERN_PACKAGE',len(media),'images',json.dumps(delta))
