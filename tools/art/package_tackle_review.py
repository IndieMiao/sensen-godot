#!/usr/bin/env python3
"""Label inspected runtime media and retain auditable SGODOT-214 evidence."""
from pathlib import Path
import json,shutil,hashlib,math,colorsys,statistics,sys
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/tackle-214'
DEST=ROOT/'docs/design/tackle-shop-214-2026-10-16'
PREFIX='SGODOT-214_TACKLE_v1_'
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def font(n):return ImageFont.truetype(FONT,n)
def signature(im,title,note):
    w,h=im.size;small=w<=500;top=64 if small else 86;bottom=60 if small else 58
    result=Image.new('RGB',(w,h+top+bottom),'#fff8f1');result.paste(im,(0,top));d=ImageDraw.Draw(result)
    d.text((12 if small else 26,10),'【赵云】SGODOT-214 · TACKLE v1',fill='#513f36',font=font(15 if small else 25))
    d.text((12 if small else 26,35 if small else 45),title,fill='#654b3e',font=font(14 if small else 25))
    d.text((12 if small else 26,h+top+12),note,fill='#654b3e',font=font(11 if small else 18))
    return result
def save(name,image):
    path=DEST/(PREFIX+name+'.png');image.save(path,optimize=True);return path
def median_patch(im,point):
    x,y=point;pixels=list(im.crop((x-5,y-5,x+6,y+6)).get_flattened_data())
    return [int(statistics.median(p[i] for p in pixels)) for i in range(3)]
def main():
    DEST.mkdir(parents=True,exist_ok=True);(DEST/'.gdignore').touch()
    files=[];raw=OUT/'captures'
    entries=[('game-360-6p72m','01_game_360','游戏取景 · 43° / 6.72 m',
              '原始画面 360 × 800；边角裁切按已确认方案\nVulkan Mobile · RTX 2060 · 不含玩法 UI'),
             ('whole-43deg','02_whole_43deg','完整全景 · 43° / 10.20 m','Godot 4.7.2 · Vulkan Mobile · 6.80 × 6.40 m 主地面'),
             ('counter','03_counter','弧柜近景 · 船舵 / 小提灯 / 两条鱼 / 灰色器具','实渲近景；柜台后通道实测 1.36 m'),
             ('rod-rack','04_rod_rack','四竿木架近景 · 架旁一桶三浮漂','架 + 四竿 + 浮漂桶 = 1,196 三角面；specular 0.28'),
             ('kai-corner','05_kai_corner','Old Kai 角落 · 渔网 / 圆凳 / 船桨桶','Kai 的桶装船桨；不计入两只浮漂桶'),
             ('rafa-corner','06_rafa_corner','Rafa 角落 · 浮漂桶 / 渔网 / 盆栽','Rafa 站位已留空，右侧浮漂桶向墙端收拢')]
    for source,name,title,note in entries:files.append(save(name,signature(Image.open(raw/(source+'.png')).convert('RGB'),title,note)))
    standing=Image.open(raw/'standing-clearance.png').convert('RGB');d=ImageDraw.Draw(standing)
    anchors={a['name']:a for a in json.loads((ROOT/'assets/rooms/tackle_shop/layout.json').read_text())['anchors']}
    for name,label in [('npc_keeper','Finn'),('npc_kai','Old Kai'),('npc_rafa','Rafa'),('spawn','Player')]:
        x,y,z=anchors[name]['position'];y+=1.93
        sx=720+(x-z)/math.sqrt(2)*1440/10.2
        sy=720-((y-1.2)*math.cos(math.radians(43))-(x+z)*math.sin(math.radians(43))/math.sqrt(2))*1440/10.2
        box=d.textbbox((0,0),label,font=font(23));width=box[2]+20
        d.rounded_rectangle((sx-width/2,sy-8,sx+width/2,sy+32),radius=8,fill='#fff6e9')
        d.text((sx-width/2+10,sy-4),label,fill='#604734',font=font(23))
    files.append(save('07_standing_clearance',signature(standing,'角色尺度与建议站位','四个人物均为现有默认尺规人偶；不是 Finn / Kai / Rafa 的角色美术。')))
    ref=Image.open(ROOT/'tools/art/source/tackle_shop/reference/SGODOT-214_stark-tackle.png').convert('RGB')
    whole=Image.open(raw/'whole-43deg.png').convert('RGB')
    sheet=Image.new('RGB',(2040,1048),'#fff8f1');draw=ImageDraw.Draw(sheet)
    for x,im,label in [(0,ref,'Stark 提供定稿 · 2681:135486'),(1040,whole,'Godot Mobile 实渲 · 首版待画面验收')]:
        sheet.paste(im.resize((1000,1000),Image.Resampling.LANCZOS),(x,48));draw.text((x+20,8),label,fill='#654b3e',font=font(24))
    files.append(save('08_reference_comparison',signature(sheet,'设计图 / 运行时对照','两图镜头与物件比例未作像素配准；图中鱼竿架依已批准规格替换。')))
    ortho=Image.new('RGB',(2040,720),'#fff8f1');draw=ImageDraw.Draw(ortho)
    for i,(name,title) in enumerate([('front','正面'),('left','侧面'),('top','俯视')]):
        im=Image.open(raw/('orthographic-'+name+'.png')).convert('RGB').resize((680,680),Image.Resampling.LANCZOS)
        ortho.paste(im,(i*680,40));draw.text((i*680+20,3),title,fill='#654b3e',font=font(24))
    files.append(save('09_orthographic',signature(ortho,'交付模型正交三视','实际 Godot 模型；原始每视图 1440 × 1440，本表统一缩小。')))
    collision=Image.open(OUT/'bench/collisions.png').convert('RGB')
    files.append(save('10_collisions',signature(collision,'实际碰撞体与角色','共享 scene_bench；家具、墙边、出口和掌柜通道均经角色物理移动检查。')))
    # The series standard compares corresponding architectural bright patches.
    pairs=[('柱',(53,580),(97,650)),('梁',(390,184),(330,365)),('墙',(263,390),(315,440)),('地面',(760,1050),(880,1100))]
    samples=[];compare=sheet.copy();d=ImageDraw.Draw(compare)
    for label,a,b in pairs:
        values=[]
        for im,point,xoff in [(ref,a,0),(whole,b,1040)]:
            rgb=median_patch(im,point);h,s,v=colorsys.rgb_to_hsv(*(c/255 for c in rgb));values.append({'point':point,'rgb8':rgb,'hue_degrees':h*360,'saturation':s})
            sx=xoff+point[0]*1000/im.width;sy=48+point[1]*1000/im.height
            d.rectangle((sx-8,sy-8,sx+8,sy+8),outline='#c82d61',width=3);d.text((sx+10,sy-20),label,fill='#c82d61',font=font(23))
        delta=abs(values[0]['hue_degrees']-values[1]['hue_degrees']);delta=min(delta,360-delta)
        samples.append({'component':label,'reference':values[0],'runtime':values[1],'hue_difference_degrees':delta,'passed':delta<=10})
    assert all(s['passed'] for s in samples),samples
    max_delta=max(s['hue_difference_degrees'] for s in samples)
    files.append(save('11_color_samples',signature(compare,'对应柱 / 梁 / 墙 / 地面取色位置',f'11 × 11 px 中位数；四处色相差最大 {max_delta:.2f}°；不是全图相似度或画面验收。')))
    (DEST/'color-validation.json').write_text(json.dumps({'method':'Corresponding architectural patches; 11x11 RGB median; circular HSV hue difference',
       'limit_degrees':10,'max_difference_degrees':max_delta,'samples':samples},ensure_ascii=False,indent=2)+'\n')
    evidence=[(OUT/'glb-validation.json','glb-validation.json'),(raw/'godot-validation.json','godot-validation.json'),
        (OUT/'atlas-detail-validation.json','atlas-detail-validation.json'),(OUT/'bench/result.json','scene-bench-result.json'),
        (OUT/'bench/scale-measurements.json','scale-measurements.json'),(OUT/'bench/video-metadata.json','video-metadata.json'),
        (OUT/'bench/window-capture.json','window-capture.json')]
    for source,name in evidence:shutil.copy2(source,DEST/name)
    # The large video stays under output; it is delivered as a Plane attachment.
    delivery_video=OUT/(PREFIX+'12_walkthrough.mp4');shutil.copy2(OUT/'bench/walkthrough.mp4',delivery_video)
    files.append(delivery_video)
    records=[{'path':str(p.relative_to(ROOT)),'name':p.name,'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]
    (OUT/'delivery-files.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
    (DEST/'media-manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
    print('REVIEW_PACKAGE',len(files),'files; max structural hue difference',max_delta)

def package_spawn():
    raw=OUT/'spawn-captures/game-spawn-follow-360.png'
    path=save('13_spawn_follow_360',signature(Image.open(raw).convert('RGB'),
        '进门跟随取景 · 43° / 6.72 m',
        '360 × 800；玩家在 spawn，镜头跟随玩家\nFinn 为现有造型；Vulkan Mobile / RTX 2060'))
    shutil.copy2(OUT/'spawn-captures/spawn-follow-validation.json',DEST/'spawn-follow-validation.json')
    record={'path':str(path.relative_to(ROOT)),'name':path.name,'size':path.stat().st_size,
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    for file in [DEST/'media-manifest.json',OUT/'delivery-files.json']:
        rows=json.loads(file.read_text())
        rows=[r for r in rows if r['name']!=path.name]+[record]
        file.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
    print('SPAWN_REVIEW_PACKAGED',path.name)

if __name__=='__main__':
    if '--spawn-only' in sys.argv:package_spawn()
    else:main()
