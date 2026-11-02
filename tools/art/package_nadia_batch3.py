#!/usr/bin/env python3
"""Package Nadia's inspected game captures and the requested three-resident comparison."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image, ImageDraw
from package_npc_batch3 import sheet, font

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'docs/design/npc-parts-batch3-2026-10-29/nadia'
parser = argparse.ArgumentParser()
parser.add_argument('--runtime-root', type=Path, required=True)
args = parser.parse_args()
runtime = args.runtime_root.resolve()
source = runtime / 'output/npc-batch3'
DEST.mkdir(parents=True, exist_ok=True)
(DEST / '.gdignore').touch()
media = []


def read(path): return Image.open(path).convert('RGB')


def save(issue, suffix, picture, title, note):
    prefix = 'SGODOT-347_NADIA_v1_' if issue == 347 else 'SGODOT-362_PARTS_v1_'
    image = Image.new('RGB', (picture.width, picture.height + 116), '#f5f6f3')
    image.paste(picture, (0,72))
    draw = ImageDraw.Draw(image)
    draw.text((20,10), '【赵云】SGODOT-%d · NPC BATCH 3 v1' % issue, font=font(24), fill='#243b43')
    draw.text((20,40), title, font=font(20), fill='#243b43')
    draw.text((20,image.height-34), note, font=font(15), fill='#526970')
    path = DEST / (prefix + suffix + '.png')
    image.save(path, optimize=True)
    media.append({'issue':issue,'name':path.name,'path':str(path.relative_to(ROOT)),
                  'size':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})


def card(name): return read(source/'nadia-portraits'/(name+'_card.jpg'))


save(347,'01_before_after',sheet([('Nadia · 原花冠 / 蓝条纹',card('nadia_now')),
                                 ('Nadia · 矮软帽 / 米白围裙',card('nadia_new'))],400,2),
     '居民卡舞台 · 原造型 / 新造型','farm-dev checkout · Godot 4.7.2 / Vulkan Mobile · 原赤褐长发，暖粉条纹，空胸袋。')
for number,key,title in [('02','nadia_hat','矮软面包师帽 · 原长发保留'),
                          ('03','nadia_apron','浅米白围裙 · 肩带 / 空胸袋 / 后腰系带')]:
    items = [(label+' · '+state_label,read(source/'nadia-closeups'/(key+'_'+state+'_'+side+'.png')))
             for side,label in [('front','正面'),('back','背面')]
             for state,state_label in [('before','底件'),('after','新件')]]
    save(347,number+'_'+key,sheet(items,460,2),title,
         '成对镜头和灯光一致；一个 mesh / surface；原 FBX 节点、变换、骨架与绑定矩阵保留。')
save(347,'04_market_lineup',sheet([('Mei · 棕围裙',card('mei')),('Theo',card('theo')),
                                 ('Nadia · 新',card('nadia_new'))],300,3),
     '集市同屋 · Mei / Theo / Nadia','未修改 resident portrait baker；逐人游戏实渲后并排，正式 NPC slots 由程序接入。')
motion = json.loads((source/'nadia-motion/motion-validation.json').read_text())
save(347,'05_motion',sheet([(e['motion']+' %.2fs / %d°'%(e['time'],round(e['yaw']*180/3.14159265)),
                            read(source/'nadia-motion'/e['name'])) for e in motion['captures']],250,4),
     '站立 / 行走 / 侧背面检查','原动画 pose 取样；检查围裙下摆、胸袋和肩带，未改骨骼或动画。')
save(347,'06_native_badge_72px',read(source/'nadia-motion/native_badge_72px.png'),
     '原生名字条 + 72 屏幕像素徽标',
     '游戏 UiNpcNameTag / StatusBadge，36 逻辑 px × 2；原生 2.0 m 名字锚点。')
save(362,'07_lena_rafa_nadia',sheet([('Lena · 新雨帽',card('lena_new')),('Rafa · 新帽 / 横纹',card('rafa_new')),
                                    ('Nadia · 新帽 / 围裙',card('nadia_new'))],300,3),
     '三人新造型 · Lena / Rafa / Nadia','同一居民卡舞台与原生渲染；本批共五件 NPC 专用新部件，未修改造型数据。')
for path,name in [(source/'nadia-validation.json','godot-validation.json'),
                  (source/'nadia-motion/motion-validation.json','motion-validation.json'),
                  (source/'nadia-closeups/render-validation.json','render-validation.json'),
                  (source/'looks-phase2.json','looks-phase2.json'),
                  (ROOT/'tools/art/source/npc_batch3/nadia-geometry-validation.json','geometry-validation.json'),
                  (runtime/'reports/report_2/results.xml','tests.xml')]:
    shutil.copy2(path,DEST/name)
(DEST/'media-manifest.json').write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print('NADIA_REVIEW',len(media),'images')
