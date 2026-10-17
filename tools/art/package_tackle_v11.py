#!/usr/bin/env python3
"""SGODOT-214 v1.1 signed review, HSV/value evidence and full handoff manifest."""
from pathlib import Path
import json,hashlib,shutil,colorsys,math,statistics
from PIL import Image,ImageDraw
from package_tackle_review import signature,font,median_patch
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/tackle-214';RAW=OUT/'captures'
DEST=ROOT/'docs/design/tackle-shop-214-v1.1-2026-10-16'
PREFIX='SGODOT-214_TACKLE_v1_1_'
files=[]
def save(name,im,title,note):
    path=DEST/(PREFIX+name+'.png');signature(im,title,note,'v1.1').save(path,optimize=True);files.append(path)
def read(path):return Image.open(path).convert('RGB')
def panels(images,width=800):
    # Every source keeps its aspect. Blank space is an explicitly labelled sheet.
    height=max(round(im.height*width/im.width) for _,im in images)
    sheet=Image.new('RGB',(len(images)*(width+20)-20,height+44),'#fff8f1');draw=ImageDraw.Draw(sheet)
    for i,(title,im) in enumerate(images):
        h=round(im.height*width/im.width)
        sheet.paste(im.resize((width,h),Image.Resampling.LANCZOS),(i*(width+20),44))
        draw.text((i*(width+20)+12,4),title,fill='#654b3e',font=font(22))
    return sheet
def color(im,point):
    rgb=median_patch(im,point);h,s,v=colorsys.rgb_to_hsv(*(c/255 for c in rgb))
    linear=[c/255/12.92 if c/255<=.04045 else ((c/255+.055)/1.055)**2.4 for c in rgb]
    y=sum(a*b for a,b in zip(linear,[.2126,.7152,.0722]))
    lum=116*(y**(1/3) if y>(6/29)**3 else y/(3*(6/29)**2)+4/29)-16
    return {'point':list(point),'rgb8':rgb,'hue':h*360,'saturation':s,'value':v,'L_star':lum}
def main():
    DEST.mkdir(parents=True,exist_ok=True);(DEST/'.gdignore').touch()
    save('01_spawn_follow_360',read(OUT/'spawn-captures/game-spawn-follow-360.png'),'进门默认跟随 · 43° / 6.72 m',
         '360 × 800；玩家站在 spawn，镜头跟随玩家\nFinn 为现有造型；柜台后通道 0.90 m')
    save('02_whole_43deg',read(RAW/'whole-43deg.png'),'完整全景 · 2.60 m 锚纹毯 / 后移柜台 / 暖桃墙',
         'Godot 4.7.2 · Vulkan Mobile / RTX 2060 · 主地面 6.80 × 6.40 m')
    save('03_counter',read(RAW/'counter.png'),'柜台后移 0.46 m · 保留鱼缸玻璃材质','各 surface 保留导入材质；柜台后通道实测 0.90 m。')
    save('04_rod_rack',read(RAW/'rod-rack.png'),'四竿陈列架 · 哑光卷线轮','架 + 四竿 + 桶：1,196 三角面；specular 0.28；全屋仍只有两只浮漂桶。')
    save('05_wall_decor',read(RAW/'wall-decoration.png'),'放大鱼形木牌 / 彩旗 / 壁灯','鱼牌约 1.24 m；旗串约 1.51 m；壁灯 1.55 倍，并有实际局部暖光。')
    save('06_floor_dressing',panels([('左墙绳卷木箱',read(RAW/'rope-crate.png')),('Rafa 一侧鱼篓 / 桶 / 渔网',read(RAW/'rafa-corner.png'))]),
         '补充墙脚陈设密度','两件新落地道具均有 layout 碰撞；居民和玩家站位留空。')
    save('07_kai_rafa',panels([('Old Kai 左前角',read(RAW/'kai-corner.png')),('Rafa 右前角',read(RAW/'rafa-corner.png'))]),
         '两位居民角落','Kai / Rafa 建议站位保持 v1 的对称关系；坐凳、船桨桶、两张渔网保留。')
    reference=read(ROOT/'tools/art/source/tackle_shop/reference/SGODOT-214_stark-tackle.png')
    archived=read(ROOT/'docs/design/tackle-shop-214-2026-10-16/SGODOT-214_TACKLE_v1_02_whole_43deg.png')
    before=archived.crop((0,86,archived.width,archived.height-58));after=read(RAW/'whole-43deg.png')
    save('08_reference_v1_v11',panels([('Stark 定稿',reference),('v1 实渲',before),('v1.1 实渲',after)],900),
         '定稿 / v1 / v1.1 对照','v1 与 v1.1 使用同一整间镜头；定稿为示意图，未作像素配准。')
    off=read(RAW/'whole-lamps-off.png')
    save('09_lamp_control',panels([('三盏局部灯关闭',off),('三盏局部灯开启',after)]),
         '同镜头灯光控制','环境光、太阳、材质、贴图均相同；只切换壁灯、吊灯、柜台提灯的实际光源。')
    save('10_collisions',read(OUT/'bench/collisions.png'),'真实装配碰撞体','游戏 P0RoomNav 从这些 CollisionShape3D 构建可走网格；没有使用 floor_size / boundaries 回退。')
    save('11_orthographic',panels([(title,read(RAW/('orthographic-'+name+'.png'))) for name,title in [('front','正面'),('left','侧面'),('top','俯视')]],650),
         '交付模型正交三视','来自同一批实际导入 GLB；未改变房间尺寸。')
    # Use corresponding architectural surfaces, retaining old/new samples at
    # identical runtime pixels. Track hue AND saturation/value/perceived lightness.
    pairs=[('墙',(263,390),(315,400)),('柱',(53,580),(97,650)),('梁',(390,184),(330,365)),('地面',(760,1050),(880,1100))]
    records=[]
    for label,a,b in pairs:
        row={'component':label,'reference':color(reference,a),'v1':color(before,b),'v1_1':color(after,b)}
        for version in ('v1','v1_1'):
            source=row[version];target=row['reference'];delta=abs(source['hue']-target['hue'])
            row[version+'_difference']={'hue':min(delta,360-delta),'saturation_pp':100*(source['saturation']-target['saturation']),
               'value_pp':100*(source['value']-target['value']),'L_star':source['L_star']-target['L_star']}
        records.append(row)
    chart=Image.new('RGB',(1500,790),'#fff8f1');draw=ImageDraw.Draw(chart)
    headings=['同位置材质取样','Stark：H / S / V / L*','v1：H / S / V / L*','v1.1：H / S / V / L*']
    for x,title in zip([24,210,630,1050],headings):draw.text((x,12),title,fill='#654b3e',font=font(22))
    for i,row in enumerate(records):
        y=65+i*168;draw.text((24,y+20),row['component'],fill='#654b3e',font=font(27))
        for x,key in zip([210,630,1050],['reference','v1','v1_1']):
            c=row[key];draw.rectangle((x,y,x+110,y+60),fill=tuple(c['rgb8']))
            draw.text((x,y+68),f"{c['hue']:.1f}° / {100*c['saturation']:.1f}% / {100*c['value']:.1f}% / {c['L_star']:.1f}",fill='#654b3e',font=font(19))
            draw.text((x,y+101),f"RGB {c['rgb8']}  @ {c['point']}",fill='#806252',font=font(16))
    save('12_color_saturation_value',chart,'对应结构表面的颜色 / 饱和度 / 明暗记录','11×11 px 中位数；H/S/V 为 HSV，L* 为 D65 感知明度；这些样点不是全图相似度或画面验收。')
    (DEST/'color-value-validation.json').write_text(json.dumps({'method':'Corresponding architectural 11x11 median patches, HSV and D65 L*; same runtime pixels for v1/v1.1',
        'samples':records,'max_hue_difference':max(r['v1_1_difference']['hue'] for r in records)},ensure_ascii=False,indent=2)+'\n')
    lamp_regions={'wall_lantern':[335,320,480,450],'pendant':[650,250,835,450],'counter':[710,470,835,600]}
    deltas={}
    for name,box in lamp_regions.items():
        on_pixels=list(after.crop(box).get_flattened_data());off_pixels=list(off.crop(box).get_flattened_data())
        diff=[sum(abs(a-b) for a,b in zip(p,q))/3 for p,q in zip(on_pixels,off_pixels)]
        deltas[name]={'rectangle':box,'mean_absolute_rgb8_delta':statistics.mean(diff)}
    (DEST/'lamp-control.json').write_text(json.dumps({'same_camera_and_global_lighting':True,'regions':deltas},indent=2)+'\n')
    for source,name in [(OUT/'glb-validation.json','glb-validation.json'),(RAW/'godot-validation.json','godot-validation.json'),
          (OUT/'v11/assembly-nav-validation.json','assembly-nav-validation.json'),(OUT/'spawn-captures/spawn-follow-validation.json','spawn-follow-validation.json'),
          (OUT/'atlas-detail-validation.json','atlas-detail-validation.json'),(OUT/'bench/result.json','scene-bench-result.json'),
          (OUT/'bench/scale-measurements.json','scale-measurements.json'),(OUT/'bench/video-metadata.json','video-metadata.json'),
          (OUT/'bench/window-capture.json','window-capture.json')]:shutil.copy2(source,DEST/name)
    video=OUT/'v11'/(PREFIX+'13_walkthrough.mp4');shutil.copy2(OUT/'bench/walkthrough.mp4',video);files.append(video)
    records=[{'path':str(p.relative_to(ROOT)),'name':p.name,'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]
    (DEST/'media-manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
    (OUT/'v11/delivery-files.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
    print('V11_REVIEW_PACKAGE',len(files),'files')

if __name__=='__main__':main()
