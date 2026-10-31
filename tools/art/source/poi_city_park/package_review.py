"""Label actual Godot captures, quantify bake controls, and package review evidence."""
from pathlib import Path
import colorsys
import hashlib
import json
import shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'output/poi-city-park-320'
CAP=OUT/'captures'
DOC=ROOT/'docs/design/poi-city-park-320-2026-10-31'
DOC.mkdir(parents=True,exist_ok=True)
REVISION='v1.2'
PREFIX='SGODOT-320_N5_'+REVISION+'_'
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
FONTS={s:ImageFont.truetype(FONT,s) for s in [13,17,21,25,30]}
MEDIA=[]


def save(image,suffix):
    path=DOC/(PREFIX+suffix+'.png')
    image.save(path)
    MEDIA.append(path)


def label(image,title,subtitle='',font_size=21):
    probe=ImageDraw.Draw(image)
    lines=['']
    for character in subtitle:
        if probe.textlength(lines[-1]+character,font=FONTS[13])>image.width-36:lines.append('')
        lines[-1]+=character
    header=46+18*len(lines)
    canvas=Image.new('RGB',(image.width,image.height+header+36),'#f3f5f2')
    canvas.paste(image,(0,header))
    draw=ImageDraw.Draw(canvas)
    draw.text((18,6),title,font=FONTS[font_size],fill='#244333')
    for i,line in enumerate(lines):draw.text((18,36+i*18),line,font=FONTS[13],fill='#53675c')
    draw.text((18,canvas.height-29),'【黄忠】 SGODOT-320 / N5 '+REVISION+' / Godot Mobile',font=FONTS[13],fill='#354b40')
    return canvas


def panel(paths,titles,width=720):
    images=[Image.open(p).convert('RGB') for p in paths]
    height=max(round(im.height*width/im.width) for im in images)
    canvas=Image.new('RGB',(width*len(images),height+45),'#f3f5f2')
    draw=ImageDraw.Draw(canvas)
    for i,(image,title) in enumerate(zip(images,titles)):
        resized=ImageOps.contain(image,(width,height),Image.Resampling.LANCZOS)
        canvas.paste(resized,(i*width+(width-resized.width)//2,45+(height-resized.height)//2))
        draw.text((i*width+20,7),title,font=FONTS[21],fill='#244333')
    return canvas


def colour_controls():
    results=[]
    rows=[]
    for source in ['tree_0','deco_fence','deco_bench']:
        left=CAP/('farm_original_'+source+'.png');right=CAP/('atlas_baked_'+source+'.png')
        a=np.asarray(Image.open(left).convert('RGB')).astype(float)
        b=np.asarray(Image.open(right).convert('RGB')).astype(float)
        background=a[0,0]
        mask=(np.linalg.norm(a-background,axis=2)>20)&(np.linalg.norm(b-background,axis=2)>20)
        mask=np.asarray(Image.fromarray((mask*255).astype('uint8')).filter(ImageFilter.MinFilter(5)))>0
        ca=np.median(a[mask],axis=0)/255;cb=np.median(b[mask],axis=0)/255
        ha,sa,va=colorsys.rgb_to_hsv(*ca);hb,sb,vb=colorsys.rgb_to_hsv(*cb)
        hue=min(abs(ha-hb),1-abs(ha-hb))*360
        row={'source':source,'same_camera_light_geometry':True,'eroded_object_pixels':int(mask.sum()),
             'median_source_srgb':ca.tolist(),'median_baked_srgb':cb.tolist(),
             'median_hue_delta_degrees':hue,'median_value_delta':vb-va,
             'object_rgb_mae_255':float(np.abs(a[mask]-b[mask]).mean()),
             'passed':bool(hue<=10 and vb>=va-.05)}
        results.append(row)
        row_image=panel([left,right],['农场原件 / '+source,'N5 图集烘后 / 同光同机位'],560)
        rows.append(row_image)
    image=Image.new('RGB',(1120,sum(r.height for r in rows)),'#f3f5f2')
    y=0
    for row in rows:image.paste(row,(0,y));y+=row.height
    return results


def main():
    geometry=json.loads((OUT/'geometry-validation.json').read_text())
    source=json.loads((OUT/'source-validation.json').read_text())
    godot=json.loads((CAP/'godot-validation.json').read_text())
    assert geometry['passed'] and source['passed'] and godot['passed']
    assert godot['imported']['triangles']==geometry['placed_triangles']
    assert godot['imported']['surfaces']==geometry['placed_surfaces']
    assert all((CAP/'godot-validation.json').stat().st_mtime >= path.stat().st_mtime
               for path in CAP.glob('*.png')), 'Wait for the current capture run to finish'
    for directory in ['assets/rooms/poi_city_park','assets/rooms/_shared/shell_park','scenes/poi_city_park']:
        for extension in ['*.import','*.gd.uid']:
            for imported in (OUT/'project'/directory).glob(extension):
                shutil.copy2(imported,ROOT/directory/imported.name)
    default=Image.open(CAP/'default_43deg_360.png').convert('RGB')
    save(label(default,'N5 / 默认进门镜头','43° / yaw 45° / 6.72m / 360px',17),'default_43deg_360')
    for name,title,subtitle in [('panorama','N5 城市绿地 / 整园全景','43° / 远景低灌木遮住接地线；全景非默认 6.72m 镜头')]:
        save(label(Image.open(CAP/(name+'.png')).convert('RGB'),title,subtitle),name)
    colours=colour_controls()
    # The world and camera are unchanged; only the existing water shader advances.
    a=np.asarray(Image.open(CAP/'water_t0.png').convert('RGB')).astype(float)
    b=np.asarray(Image.open(CAP/'water_t1.png').convert('RGB')).astype(float)
    delta=np.max(abs(a-b),axis=2)
    water={'different_pixels_gt_2':int((delta>2).sum()),'max_channel_delta_255':float(delta.max()),
           'mean_abs_rgb_delta_255':float(np.abs(a-b).mean()),'passed':int((delta>2).sum())>50}
    pixels=[]
    for name in ['default_43deg_360','panorama','minimum_zoom_360','bench_seated_detail']:
        image=np.asarray(Image.open(CAP/(name+'.png')).convert('RGB'))
        pixels.append({'capture':name,'rgb_std':float(image.std()),'passed':bool(image.std()>20)})
    validation={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
                'geometry':geometry,'source':source,'godot':godot,'colour_controls':colours,'water_motion':water,'pixel_checks':pixels,
                'scope':'Desktop Vulkan Mobile art review; no gameplay integration or device performance acceptance.'}
    validation['passed']=all(c['passed'] for c in colours) and water['passed'] and all(p['passed'] for p in pixels)
    assert validation['passed'],(colours,water,pixels)
    path=DOC/(PREFIX+'validation.json');path.write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n');MEDIA.append(path)
    table=['# N5 '+REVISION+' 实测模块表','', '尺寸从最终 GLB 顶点读取，单位 m。轴顺序为 X 宽 / Y 高 / Z 深。', '',
           '| 模块 | 三角形 | surface | X × Y × Z |','|---|---:|---:|---|']
    for name,data in geometry['assets'].items():
        table.append(f'| {name} | {data["triangles"]} | {data["surfaces"]} | '+ ' × '.join(f'{v:.3f}' for v in data['dimensions_m'])+' |')
    table+=['',f'摆放后：{geometry["placed_triangles"]:,} 三角形 / {geometry["placed_surfaces"]} surface；植物 {geometry["plant_triangles"]:,} 三角形。',
            'white_fence_segment、bench_farm_control、bush_control 为保色/源件控制，不计入实际摆放。',
            '喷泉石材 1,876 面（原 2,076 面扣除两片静态水）；独立动态水体 784 面。原喷泉 bounds 与尺寸保持不变。',
            '绿椅现宽 1.400m、顶高 0.950m、座面 0.715m，两座中心距 0.700m。白椅宽 1.040m，仅装饰。',
            '入口侧圆灌木实测顶高 0.900m，v1.2 给两实例补上顶点 bounds 盒体碰撞。白石 16 个短尖角，外半径 1.00m。外围草地为 60×60m，非可走区域。',
            '远景前沿 21 株低灌木合成一个 surface，使用同一图集、无碰撞、不投影，随远景卡朝向移动；原 v1.1 所有网格几何保持不变。',
            '玫瑰拱保留农场 pergola 立柱，改弧顶与玫瑰；路灯与空白入口牌新制。绿桶新制已获上官婉儿 77a66827 确认。']
    path=DOC/(PREFIX+'asset_table.md');path.write_text('\n'.join(table)+'\n');MEDIA.append(path)
    media=[]
    for path in MEDIA:
        record={'file':path.name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'}
        if path.suffix=='.png':record['pixels']=list(Image.open(path).size)
        media.append(record)
    (DOC/(PREFIX+'media-manifest.json')).write_text(json.dumps(media,indent=2)+'\n')
    print(json.dumps({'colour_controls':colours,'water':water,'files':len(MEDIA)},indent=2))


if __name__=='__main__':main()
