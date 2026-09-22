#!/usr/bin/env python3
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from PIL import Image
import json, math, html, io, sys
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/ui-handoff-2026-09-16'
PACK=OUT/'Sensen-0.11.0-UI设计交接'
DEST=PACK/'街角四季-0.11.0-界面图册.pdf'
items=json.loads((PACK/'界面清单.json').read_text())
pdfmetrics.registerFont(TTFont('Chinese','/Library/Fonts/Arial Unicode.ttf'))
W,H=960,1080
c=canvas.Canvas(str(DEST),pagesize=(W,H),pageCompression=1)
c.setTitle('街角四季 0.11.0 - 当前版本界面与美术交接')
c.setAuthor('Sensen')
INK='#233E33';MUTED='#62756A';GREEN='#237B5B';PAPER='#F2F5EE'
page=0;log=[]
style=ParagraphStyle('body',fontName='Chinese',fontSize=16,leading=26,textColor=HexColor(INK),wordWrap='CJK')
def text(s,x,y,width,size=16,color=INK):
    st=ParagraphStyle('p',parent=style,fontSize=size,leading=size*1.65,textColor=HexColor(color))
    p=Paragraph(html.escape(s).replace('\n','<br/>'),st);_,height=p.wrap(width,10000)
    p.drawOn(c,x,y-height);return y-height

def begin(label,title,subtitle=''):
    global page
    page+=1;c.setFillColor(HexColor(PAPER));c.rect(0,0,W,H,fill=1,stroke=0)
    c.setFillColor(HexColor(GREEN));c.rect(40,H-56,5,18,fill=1,stroke=0)
    text(label,56,H-36,850,11,MUTED)
    y=text(title,40,H-75,880,25)
    if subtitle:y=text(subtitle,40,y-10,875,12,MUTED)
    c.setStrokeColor(HexColor('#D7E1D4'));c.line(40,46,W-40,46)
    text('SENSEN / UI HANDOFF / 0.11.0 / 2026-09-16',40,33,760,9,MUTED)
    text(f'{page:03d}',W-78,34,45,10,MUTED)
    return y-24

def image_on(img,x,y,w,maxh):
    if not isinstance(img,Image.Image):img=Image.open(img).convert('RGB')
    s=min(w/img.width,maxh/img.height);iw,ih=img.width*s,img.height*s
    c.drawImage(ImageReader(img),x,y-ih,width=iw,height=ih,mask='auto');return ih

start=begin('ART DIRECTION REFERENCE','街角四季 · 当前版本界面图册','原始界面截图与文字说明 / Android 0.11.0 (2026091607)')
text('把当前界面交给 UI 与美术设计',40,start-20,870,29)
y=text(f'{len(items)} 个界面与主要状态，附完整滚动内容。\n页面图片来自当前组件在 Android 模拟器中的实际渲染，分辨率 720 × 1560 px。',40,start-83,870,19)
thumb_ids=['04-map','20-farm','30-bag','70-mine-floor-5']
for n,id in enumerate(thumb_ids):
    r=next((r for r in items if r['id']==id),items[n])
    image_on(PACK/'screens'/r['image'],40+n*226,y-35,204,446)
    text(r['title'],40+n*226,y-494,208,13)
y=text('交接包包含：手机首屏 PNG、完整长图/横条图、滚动原始片段、离线 HTML 图册和 CSV 界面清单。',40,y-554,870,17)
text('展示账号和进度用于打开各类界面，不包含正式玩家的私人数据。编号 90 起为旧存档兼容与内部工具附录；主流程与附录分别标明。',40,y-25,870,14,MUTED)
c.showPage()
# Module index with actual screen counts.
top=begin('CONTENTS','按功能查阅','PDF 每个界面保留手机首屏，滚动长内容另附续页；素材包提供完整 PNG')
groups=list(dict.fromkeys(r['category'] for r in items));y=top
for g in groups:
    count=sum(r['category']==g for r in items)
    y=text(g,42,y,670,20);text(f'{count} 个界面 / 状态',745,y+33,175,14,MUTED)
    c.setStrokeColor(HexColor('#D7E1D4'));c.line(40,y-14,920,y-14);y-=47
text('阅读说明',40,y-10,880,20)
text('1. 首屏反映手机上的真实布局；有长内容的页面紧随其后提供滚动续页。\n2. 完整长图只保留一次固定页头/页尾，拼接的是实际滚动内容。\n3. 横向列表按顺序分行展示，素材包中的完整横条保留原始连续布局。\n4. 图中已有的截断、留白或样式不一致是当前产品现状，未在截图中重绘或修饰。',40,y-56,875,14,MUTED)
c.showPage()
asset_notes={
'01':'页面背景、地图浮层、角色标记、农场微缩图、底部图标和选择卡片。',
'02':'换装背景、角色取景、分类图标、部件缩略图、选中态、还原/完成与反馈区。',
'03':'农场场景、作物状态、种子卡片、摊位列表、购买/出售按钮及消息反馈。',
'04':'物品图标、网格、分类/搜索、属性对比、装备槽、委托卡片和确认操作。',
'05':'地点背景、居民与道具、对话/功能面板、配方列表、材料需求及编辑按钮。',
'06':'街区建筑、角色与居民、聚会布置、目标引导、拜访入口与进入确认。',
'07':'矿层场景、矿石与怪物、生命/进度条、摇杆、攻击、楼层及电梯状态。',
'08':'队伍成员列表、邀请码、权限开关、语音状态、讲话提示和二次确认。',
'09':'旧存档保留的标签、列表、剧情和内部工具；请先确认是否纳入重设计范围。'}
for i,r in enumerate(items):
    top=begin(r['category']+' / '+r['id'],r['title'])
    c.bookmarkPage(r['id']);c.addOutlineEntry(r['title'],r['id'],level=0,closed=True)
    ih=image_on(PACK/'screens'/r['image'],40,top,400,top-70)
    x=478;y=top-6
    y=text('入口',x,y,435,12,GREEN);y=text(r['entry'],x,y-8,435,18)-28
    y=text('界面说明',x,y,435,12,GREEN);y=text(r['description'],x,y-8,435,17)-26
    y=text('可加工要素',x,y,435,12,GREEN);y=text(asset_notes[r['category'][:2]],x,y-8,435,16)-26
    if r.get('note'):
        y=text('展示状态',x,y,435,12,GREEN);y=text(r['note'],x,y-8,435,15)-25
    if r['scrolls']:
        y=text('完整内容',x,y,435,12,GREEN)
        msg='本页包含'+ '、'.join(dict.fromkeys('竖向滚动' if s['axis']=='vertical' else '横向滚动' for s in r['scrolls']))+'。后附全部内容续页，素材包 full/ 下有连续原图。'
        y=text(msg,x,y-8,435,15)-25
    y=text('原始文件',x,y,435,12,GREEN);text('screens/'+r['image'],x,y-8,435,11,MUTED)
    log.append({'id':r['id'],'page':page,'source':r['image']})
    c.showPage()
    for f in r['full_images']:
        if f['kind']!='content':continue
        im=Image.open(PACK/'full'/f['file']).convert('RGB')
        if f['axis']=='vertical':
            # At 0.72 scale, typical app text stays comparable to a printed 14pt label.
            scale=min(1.0,590/im.width);chunk=math.floor(855/scale);overlap=40
            starts=list(range(0,max(1,im.height-overlap),chunk-overlap))
            for n,offset in enumerate(starts):
                piece=im.crop((0,offset,im.width,min(im.height,offset+chunk)))
                top=begin(r['category']+' / '+r['id'],r['title']+' · 完整滚动内容',f'竖向内容 {n+1}/{len(starts)} · 与相邻页保留少量重叠，便于连续阅读')
                image_on(piece,40,top,590,top-70)
                text('实际滚动内容',672,top-5,242,13,GREEN)
                text('固定标题和底部操作请参见该界面首屏。此页保持内容字号，不将整张长图压缩到一页。',672,top-43,242,14)
                text('连续原图：\nfull/'+f['file'],672,top-180,242,10,MUTED)
                log.append({'id':r['id'],'page':page,'long':f['file'],'offset':offset})
                c.showPage()
        else:
            # Wrap continuous horizontal strips into readable rows, preserving all pixels.
            width=860;scale=min(1.0,width/im.width);cols=math.ceil(im.width/860)
            rowsper=max(1,int(800/(im.height+30)))
            for batch in range(0,cols,rowsper):
                top=begin(r['category']+' / '+r['id'],r['title']+' · 横向列表全部内容','原横向列表按从左到右顺序分行展示；完整横条另存于素材包')
                yy=top
                for n in range(batch,min(cols,batch+rowsper)):
                    crop=im.crop((n*860,0,min(im.width,(n+1)*860),im.height))
                    image_on(crop,40,yy,860,im.height);yy-=im.height+30
                log.append({'id':r['id'],'page':page,'horizontal':f['file']});c.showPage()
c.save()
(OUT/'pdf-pages.json').write_text(json.dumps({'pages':page,'entries':log},ensure_ascii=False,indent=2))
print(json.dumps({'pdf':str(DEST),'pages':page,'screens':len(items)},ensure_ascii=False))
