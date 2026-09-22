#!/usr/bin/env python3
"""Assemble observed Android screenshots; never redraw app content."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, math, html, shutil, csv, zipfile, hashlib, re
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'output/ui-handoff-2026-09-16'
PACK = OUT/'Sensen-0.11.0-UI设计交接'
FONT = '/Library/Fonts/Arial Unicode.ttf'
for folder in ['screens','full','segments']: (PACK/folder).mkdir(parents=True,exist_ok=True)
items=json.loads((OUT/'catalog.json').read_text())
checks=[]
# Use specific descriptions for repeated scene-panel patterns.
for item in items:
    key=item['id']
    if key.startswith('51-'):
        if key.endswith('-workbench'): item['description']='列出手作与装备配方，展示物品图标、所需材料、持有数量、已拥有或可制作状态；点击制作会消耗对应材料。'
        elif key.endswith('-counter'): item['description']='厨房料理列表包含配方、材料数量、料理效果和制作按钮；可用于统一料理卡片、数值行及禁用状态。'
        elif '-project_' in key: item['description']='展示建设阶段、追踪按钮、设施收益、材料需求和建造入口；完成后的设施使用页另行收录。'
        elif '-discovery_' in key: item['description']='探索点展示解锁所需的手作、安装入口或本轮可采集资源选择；包含资源图标和剩余次数提示。'
        elif key.endswith('-resident'): item['description']='居民介绍、好感状态、交流选项与委托入口；展开委托后可查看需求与交付操作。'
        elif key.endswith('-trail') or key.endswith('-board'): item['description']='展示可探索路线、剩余资源与前往入口。已开始的路线与不可立即重复的路线通过按钮状态区分。'
        elif key.endswith('-table'): item['description']='餐桌交流和分享料理入口，结合居民委托展示需求、持有量和交付按钮。'
        elif key.endswith('-path'): item['description']='花园侧路的开放条件、资源消耗或开放后的通行入口。'
        elif key.endswith('-planter'): item['description']='庭院摆件与种植的操作入口，可进入摆件编辑或给花盆种植作物。'
    if key.startswith('90-legacy-'):
        labels={'people':'居民','人':'居民','choices':'收获用途','project':'建设篮子','growth':'成长选择','decorations':'摆件布置','kitchen':'厨房','journal':'手册','events':'邻里故事'}
        for a,b in labels.items():
            if item['title'].endswith(' / '+a): item['title']=item['title'][:-len(a)]+b
for item in items:
    src=OUT/'raw'/item['image']; im=Image.open(src).convert('RGB')
    assert im.size==(720,1560),(src,im.size)
    shutil.copyfile(src,PACK/'screens'/src.name)
    item['full_images']=[]
    for index,scroll in enumerate(item['scrolls']):
        axis=scroll['axis'];x,y,w,h=scroll['rect'];extent=scroll['extent'];maximum=scroll['max']
        scale=(h if axis=='vertical' else w)/extent
        parts=scroll['parts'];assert parts[0]['offset']==0
        assert parts[-1]['offset']>=maximum-1
        target=round((maximum+extent)*scale)
        stitched=Image.new('RGB',(w,target) if axis=='vertical' else (target,h))
        covered=0
        for part in parts:
            pic=Image.open(OUT/'raw'/part['file']).convert('RGB')
            start=round(part['offset']*scale);size=h if axis=='vertical' else w
            assert start<=covered,(item['id'],'gap',start,covered)
            cut=max(0,covered-start);take=min(size-cut,target-covered)
            if take>0:
                area=(x,y+cut,x+w,y+cut+take) if axis=='vertical' else (x+cut,y,x+cut+take,y+h)
                stitched.paste(pic.crop(area),(0,covered) if axis=='vertical' else (covered,0))
                covered+=take
            shutil.copyfile(OUT/'raw'/part['file'],PACK/'segments'/part['file'])
        assert covered>=target-2,(item['id'],covered,target)
        name=f"{item['id']}-{index+1}-{axis}.png"
        stitched.save(PACK/'full'/name,optimize=True)
        item['full_images'].append({'file':name,'axis':axis,'kind':'content','size':list(stitched.size)})
        if axis=='vertical':
            # Retain fixed header/footer exactly once, and align content at its original x.
            full=Image.new('RGB',(720,1560+target-h),(244,248,240))
            first=Image.open(OUT/'raw'/parts[0]['file']).convert('RGB');last=Image.open(OUT/'raw'/parts[-1]['file']).convert('RGB')
            full.paste(first.crop((0,0,720,y)),(0,0))
            # Side margins are sampled from the original panel boundary, not invented UI.
            fill=first.crop((0,y,720,y+1)).resize((720,target))
            full.paste(fill,(0,y));full.paste(stitched,(x,y))
            full.paste(last.crop((0,y+h,720,1560)),(0,y+target))
            name=f"{item['id']}-{index+1}-完整长图.png";full.save(PACK/'full'/name,optimize=True)
            item['full_images'].append({'file':name,'axis':axis,'kind':'screen','size':list(full.size)})
        checks.append({'id':item['id'],'axis':axis,'parts':len(parts),'coverage':covered,'expected':target})

def category(r):
    n=int(re.match(r'\d+',r['id'])[0])
    return '01 城市与地图' if n<10 else '02 换装' if n<20 else '03 农场与摊位' if n<30 else '04 背包、角色与委托' if n<50 else '05 地点与制作' if n<60 else '06 街区与拜访' if n<70 else '07 矿井与战斗' if n<80 else '08 多人与语音' if n<90 else '09 旧存档与内部附录'
for r in items:r['category']=category(r)
(PACK/'界面清单.json').write_text(json.dumps(items,ensure_ascii=False,indent=2))
(OUT/'stitch-verification.json').write_text(json.dumps({'passed':True,'screens':len(items),'scroll_surfaces':len(checks),'checks':checks},ensure_ascii=False,indent=2))
with (PACK/'界面清单.csv').open('w',encoding='utf-8-sig',newline='') as f:
    w=csv.writer(f);w.writerow(['编号','模块','界面','入口','说明','状态说明','手机截图','完整内容图','代码入口'])
    for r in items:w.writerow([r['id'],r['category'],r['title'],r['entry'],r['description'],r['note'],'screens/'+r['image'],'; '.join('full/'+i['file'] for i in r['full_images']),r['source']])
readme=f'''# 街角四季 0.11.0 · UI 与美术交接

截图基线：0.11.0 / 2026091607，2026-09-16 当前代码。Android 模拟器实际渲染，720 × 1560 px（游戏逻辑视口约 360 × 780），中文。共 {len(items)} 个界面/主要状态，{len(checks)} 处滚动内容完整采集。

## 怎么看

- 双击 `index.html`：带目录、搜索、入口说明和完整长图的图册，离线可用。
- `screens/`：每个页面的原始手机首屏 PNG，无美化、无重绘、无标注遮挡。
- `full/`：完整滚动内容；“完整长图”保留一次固定页头和页尾。横向列表另有完整横条图。
- `segments/`：实际逐段滚动截图，保留重叠区域，可核查长图拼接。
- `界面清单.csv` / `.json`：编号、说明、入口及代码路径，可导入表格继续分工。
- PDF 图册：每个界面一页，长内容另附可读的续页；原图分辨率保留。

## 设计范围与素材说明

截图使用独立展示账号和本地进度数据，未修改任何正式玩家存档。背包物品、任务进度、队伍成员和语音状态是展示样例，实际 UI 来自当前生产组件。地图使用当前 Android 地图 SDK，地图标注与 Android 权限弹窗属于系统/地图图层。个别离线、禁用、加载失败和确认状态是主动触发的状态样例。

主设计范围为城市/地图、换装、农场/摊位、背包/角色/委托、地点/制作/料理、街区/拜访、矿井战斗、多人/语音。编号 90 起为仍存在的旧存档兼容界面与内部工具，单独放在附录，避免和新玩家主流程混用。

建议美术按以下交付维度拆分：页面背景与场景、通用按钮/标签/输入框、底部面板与确认弹窗、物品与装备图标、人物与场景道具、状态图标与反馈。需覆盖正常/选中/禁用/处理中/失败状态。按钮拖动可滚动，滚动后不触发点击；列表页头和关闭入口保持可用。

## 当前素材位置

- 全局样式：`modules/ui/game_ui.gd`、`assets/ui/app_theme.tres`，中文字体 `assets/ui/fonts/NotoSansSC-Regular.otf`。
- 图标：`assets/ui/icons/lucide/`；农场/物品素材：`assets/ui/farm/`。
- 页面背景：`assets/ui/backgrounds/`；角色装配：`assets/avatar/`。
- 主要页面脚本与状态说明见界面清单。界面文案集中在 `assets/localization/zh_CN.json`。

本交接包记录“现在是什么样”，未包含新的 UI 改版设计。长图是实际滚动片段拼接，不表示手机真实显示为超长屏。所有画面保留现状，当前布局中的截断或留白可作为设计调整依据。
'''
(PACK/'先读我.md').write_text(readme)
# Standalone gallery; no server, framework or network required.
nav=[];cards=[]
for r in items:
    esc=lambda s:html.escape(str(s),quote=True)
    nav.append(f'<a href="#{esc(r["id"])}">{esc(r["title"])}</a>')
    images=''.join(f'<figure class="full"><figcaption>{"完整页面长图" if p["kind"]=="screen" else "完整滚动内容"} · {p["size"][0]} × {p["size"][1]}</figcaption><a href="full/{esc(p["file"])}" target="_blank"><img loading="lazy" src="full/{esc(p["file"])}"></a></figure>' for p in r['full_images'])
    cards.append(f'''<article id="{esc(r['id'])}" data-search="{esc(r['title']+' '+r['entry']+' '+r['category'])}"><div class="intro"><small>{esc(r['category'])} / {esc(r['id'])}</small><h2>{esc(r['title'])}</h2><p><b>入口</b>　{esc(r['entry'])}</p><p>{esc(r['description'])}</p>{'<p class="note">'+esc(r['note'])+'</p>' if r['note'] else ''}<code>{esc(r['source'])}</code></div><div class="views"><figure><figcaption>手机首屏 · 720 × 1560</figcaption><a href="screens/{esc(r['image'])}" target="_blank"><img loading="lazy" src="screens/{esc(r['image'])}"></a></figure>{images}</div></article>''')
css='''*{box-sizing:border-box}body{margin:0;background:#f3f5ef;color:#243e34;font:16px/1.7 system-ui,-apple-system,"PingFang SC",sans-serif}aside{position:fixed;inset:0 auto 0 0;width:260px;background:#fff;padding:24px 20px;overflow:auto;border-right:1px solid #dfe7dd}aside a{display:block;color:inherit;text-decoration:none;padding:6px 8px;font-size:13px;border-radius:6px}aside a:hover{background:#e6f1e7}input{width:100%;padding:12px;border:1px solid #b8cbbd;border-radius:8px;margin-bottom:18px}main{margin-left:260px;padding:40px;max-width:1800px}header{padding:28px 0 44px}h1{font-size:36px;margin:0}h2{font-size:25px;margin:8px 0 15px}p{max-width:900px}article{background:#fff;margin:0 0 30px;border:1px solid #dfe7dd;border-radius:16px;padding:28px;scroll-margin-top:20px}.intro{border-bottom:1px solid #e1e8df;margin-bottom:22px;padding-bottom:20px}small,figcaption{color:#62796d}code{font-size:12px;overflow-wrap:anywhere}.note{background:#fff3d5;padding:10px 14px;border-radius:8px}.views{display:flex;align-items:flex-start;gap:28px;overflow:auto}figure{margin:0;flex:0 0 auto}figure img{display:block;width:360px;height:auto;box-shadow:0 1px 5px #0002}figure.full img{width:auto;max-width:608px}figure.full{max-height:none}figcaption{font-size:12px;margin-bottom:9px}.hidden{display:none}@media(max-width:850px){aside{position:static;width:auto;max-height:240px}main{margin:0;padding:16px}.views{gap:16px}article{padding:16px}h1{font-size:27px}}'''
html_doc=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>街角四季 UI 与美术交接 0.11.0</title><style>{css}</style><aside><strong>街角四季 · 当前界面</strong><p>0.11.0 / 2026091607</p><input id="search" placeholder="搜索界面、功能或入口">{''.join(nav)}</aside><main><header><small>UI / ART HANDOFF · 2026-09-16</small><h1>当前版本界面图册</h1><p>{len(items)} 个界面与状态，{len(checks)} 处完整滚动内容。点击图片打开原图。展示数据用于覆盖页面；原始画面未经重绘。编号 90 起为旧存档与内部工具附录。</p><p><a href="先读我.md">交接说明</a> · <a href="界面清单.csv">界面清单 CSV</a></p></header>{''.join(cards)}</main><script>document.querySelector('#search').addEventListener('input',e=>{{let q=e.target.value.toLowerCase();document.querySelectorAll('article').forEach(x=>x.classList.toggle('hidden',!x.dataset.search.toLowerCase().includes(q)))}})</script></html>'''
(PACK/'index.html').write_text(html_doc)
# Contact sheets for visual review of every screen.
qa=OUT/'private/contact';qa.mkdir(exist_ok=True)
font=ImageFont.truetype(FONT,16)
for start in range(0,len(items),12):
    thumb=Image.new('RGB',(960,1710),'#edf1e8');draw=ImageDraw.Draw(thumb)
    for j,r in enumerate(items[start:start+12]):
        x=(j%4)*240;y=(j//4)*570
        image=Image.open(PACK/'screens'/r['image']).convert('RGB');image.thumbnail((224,492))
        thumb.paste(image,(x+8,y+45));draw.text((x+8,y+5),r['id'][:27],font=font,fill='#20382c');draw.text((x+8,y+25),r['title'][:14],font=font,fill='#20382c')
    thumb.save(qa/f'{start//12+1:02d}.jpg',quality=90)
print(json.dumps({'screens':len(items),'scroll_surfaces':len(checks),'pack':str(PACK)},ensure_ascii=False))
