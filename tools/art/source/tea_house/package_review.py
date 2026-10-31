"""Package signed real-render media, measured colour controls and movement evidence."""
from pathlib import Path
import colorsys
import hashlib
import json
import shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont,ImageOps,ImageFilter

ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent
KIT=ROOT/'assets/rooms/tea_house'
OUT=ROOT/'output/tea-216'
CAP=OUT/'captures'
DOC=ROOT/'docs/design/tea_house-2026-11-01'
PREFIX='SGODOT-216_tea_v1_'
AUTHOR='5281cd25-6a49-4df8-9802-f3e534956e80'
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
FILES=[]


def label(image,title,subtitle=''):
    text=ImageFont.truetype(FONT,13);heading=ImageFont.truetype(FONT,17 if image.width<500 else 25)
    probe=ImageDraw.Draw(image);lines=['']
    for char in subtitle:
        if probe.textlength(lines[-1]+char,font=text)>image.width-32:lines.append('')
        lines[-1]+=char
    header=48+19*len(lines)
    output=Image.new('RGB',(image.width,image.height+header+36),'#f1f4f2');output.paste(image,(0,header))
    draw=ImageDraw.Draw(output);draw.text((16,8),title,font=heading,fill='#31463c')
    for i,line in enumerate(lines):draw.text((16,42+19*i),line,font=text,fill='#53655c')
    draw.text((16,output.height-27),'【黄忠】 SGODOT-216 / v1 / Godot Mobile',font=text,fill='#53655c')
    return output


def save_image(image,name):
    path=DOC/(PREFIX+name+'.png');image.save(path);FILES.append(path)


def save_json(data,name):
    path=DOC/(PREFIX+name+'.json');path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');FILES.append(path)


def comparison(left,right,left_label,right_label,width=650,height=650):
    output=Image.new('RGB',(width*2,height+44),'#f1f4f2');draw=ImageDraw.Draw(output)
    font=ImageFont.truetype(FONT,21)
    for i,(image,title) in enumerate([(left,left_label),(right,right_label)]):
        image=ImageOps.contain(image,(width,height),Image.Resampling.LANCZOS)
        output.paste(image,(i*width+(width-image.width)//2,44+(height-image.height)//2))
        draw.text((i*width+16,8),title,font=font,fill='#31463c')
    return output


def hue(a,b):
    ha=colorsys.rgb_to_hsv(*(a/255))[0];hb=colorsys.rgb_to_hsv(*(b/255))[0]
    return float(min(abs(ha-hb),1-abs(ha-hb))*360)


def main():
    DOC.mkdir(parents=True,exist_ok=True)
    geometry=json.loads((OUT/'geometry-validation.json').read_text())
    source=json.loads((OUT/'source-validation.json').read_text())
    godot=json.loads((CAP/'godot-validation.json').read_text())
    bench=json.loads((OUT/'bench/result.json').read_text())
    video=json.loads((OUT/'bench/video-metadata.json').read_text())
    assert all(d['passed'] for d in [geometry,source,godot,bench]) and video['image_content_valid']
    assert godot['imported']['triangles']==geometry['placed_triangles']
    assert (CAP/'godot-validation.json').stat().st_mtime>=max(p.stat().st_mtime for p in CAP.glob('*.png'))
    entries=[('default_43deg_360','茶馆 / 默认进门镜头','43° / yaw 45° / 6.72m / 360px；人物 H=1.745m'),
        ('overview','Tea House / 整间全景','三桌各三座、窗下长凳三座，共 12 座；独立前沿入口，后墙木门为布景'),
        ('topdown_capsules','茶馆 / 俯视与胶囊','0.25m 半径、1.745m 高胶囊；16 个可达站位避开三位 NPC；主通道按 0.70m 验证'),
        ('seated_stool','茶馆 / 软垫圆墩坐姿','现有 sit_idle；座面离地 0.715m、世界 Y=0.795；桌面高 1.00m'),
        ('counter_coffee_corner','茶馆 / 柜台与咖啡角','Ama 柜台、两层茶具架；Hana 咖啡壶加两杯；空白招牌在后墙门上方')]
    for name,title,subtitle in entries:
        save_image(label(Image.open(CAP/(name+'.png')).convert('RGB'),title,subtitle),name)
    reference=Image.open(SRC/'reference/216-tea.png').convert('RGB')
    runtime=Image.open(CAP/'overview.png').convert('RGB')
    save_image(label(comparison(reference,runtime,'Stark 第二版定稿','Godot Mobile 实渲'),'茶馆 / 定稿与实渲',
        '坐具按用户 C43 改为圆墩，桌面按派活升至 1.0m；柜台后留 Ama 通道；两侧构成和三桌分区保留。'),'reference_comparison')
    a=np.array(runtime);b=np.array(reference)
    reference_points={'wall':[396,420],'beam':[342,242],'floor':[627,1017]}
    colours=[]
    for name,xy in godot['colour_points'].items():
        x,y=map(round,xy);u,v=reference_points[name]
        rendered=np.median(a[y-5:y+6,x-5:x+6].reshape(-1,3),axis=0)
        approved=np.median(b[v-5:v+6,u-5:u+6].reshape(-1,3),axis=0)
        delta=hue(rendered,approved)
        colours.append({'role':name,'runtime_xy':[x,y],'reference_xy':[u,v],'sample_px':11,
                        'runtime_rgb':rendered.tolist(),'reference_rgb':approved.tolist(),'hue_delta_degrees':delta,'passed':delta<=10})
    controls=[];panels=[]
    for plant in ['olive_tree','pothos']:
        left=Image.open(CAP/('plant_original_'+plant+'.png')).convert('RGB')
        right=Image.open(CAP/('plant_remapped_'+plant+'.png')).convert('RGB')
        old=np.asarray(left).astype(float);new=np.asarray(right).astype(float);background=old[0,0]
        mask=(np.linalg.norm(old-background,axis=2)>20)&(np.linalg.norm(new-background,axis=2)>20)
        mask=np.array(Image.fromarray((mask*255).astype('uint8')).filter(ImageFilter.MinFilter(5)))>0
        ca=np.median(old[mask],axis=0);cb=np.median(new[mask],axis=0);delta=hue(ca,cb)
        controls.append({'source':plant,'same_camera_light_geometry':True,'interior_pixels':int(mask.sum()),
                         'hue_delta_degrees':delta,'rgb_mae_255':float(np.abs(old[mask]-new[mask]).mean()),'passed':delta<=10})
        panels.append(comparison(left,right,'共享植物原图集 / '+plant,'茶馆单图集重映射',500,550))
    panel=Image.new('RGB',(1000,sum(p.height for p in panels)),'#f1f4f2');offset=0
    for image in panels:panel.paste(image,(0,offset));offset+=image.height
    save_image(label(panel,'茶馆 / 共享植物图集核对','保留原网格、叶片 alpha scissor 和色彩；同机位、同光照，仅 UV 图集区域不同。'),'plant_atlas_comparison')
    lights_on=np.array(Image.open(CAP/'lanterns_on.png').convert('RGB')).astype(float)
    lights_off=np.array(Image.open(CAP/'lanterns_off.png').convert('RGB')).astype(float)
    difference=np.max(np.abs(lights_on-lights_off),axis=2)
    lighting={'different_pixels_gt_3':int((difference>3).sum()),'mean_rgb_difference':float(np.abs(lights_on-lights_off).mean()),
              'passed':int((difference>3).sum())>1000,'lights':3,'test':'Same fixed camera, only three local light nodes toggled'}
    validation={'author':'黄忠','virtual_user_id':AUTHOR,'geometry':geometry,'source':source,'godot':godot,
        'scene_bench':bench,'video':video,'colour_samples':colours,'plant_controls':controls,'local_lighting':lighting,
        'scope':'Desktop Vulkan Mobile art and movement checks, not device performance or gameplay integration.',
        'desktop_presentation':'Private QA project disables VSync and caps at 60 FPS to avoid observed desktop presentation stalls; shared benchmark thresholds unchanged.'}
    validation['passed']=all(c['passed'] for c in colours+controls) and lighting['passed']
    assert validation['passed'],(colours,controls,lighting)
    save_json(validation,'validation');save_json(bench,'scene_bench_result')
    rows=['# 茶馆 v1 实测资产表','', '| 模块 | 三角形 | surface | X × Y × Z (m) |','|---|---:|---:|---|']
    for name,entry in geometry['assets'].items():
        rows.append(f'| {name} | {entry["triangles"]} | {entry["surfaces"]} | '+' × '.join(f'{x:.4f}' for x in entry['dimensions_m'])+' |')
    rows+=['',f'摆放后 {geometry["placed_triangles"]:,} 面 / {geometry["placed_surfaces"]} surface；植物 {geometry["plant_triangles"]:,} 面。',
           '桌面木件 Ø0.90m、高 1.00m；桌布略垂出桌沿，碰撞按半径 0.47m 保守处理。',
           '圆墩 Ø0.56m、坐面 0.715m；地面顶面 Y=0.08m，12 个座位世界 Y=0.795m。',
           '控制原型 round_stool_sage / round_stool_linen / wall_lantern / lantern_glow 不重复计入摆放预算。']
    path=DOC/(PREFIX+'asset_table.md');path.write_text('\n'.join(rows)+'\n');FILES.append(path)
    for source_name,suffix in [('walkthrough.mp4','walkthrough.mp4'),('collisions.png','scene_bench_collisions.png')]:
        path=DOC/(PREFIX+suffix)
        if source_name.endswith('.png'):
            label(Image.open(OUT/'bench'/source_name).convert('RGB'),'茶馆 / scene_bench 碰撞检查','共享基准原阈值；入口、家具、边界和滑墙均检查。').save(path)
        else:shutil.copy2(OUT/'bench'/source_name,path)
        FILES.append(path)
    media=[]
    for path in FILES:
        item={'file':path.name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'virtual_user_id':AUTHOR}
        if path.suffix=='.png':item['pixels']=list(Image.open(path).size)
        media.append(item)
    (DOC/(PREFIX+'media-manifest.json')).write_text(json.dumps(media,indent=2)+'\n')
    layout=json.loads((KIT/'layout.json').read_text())
    anchors=['<!-- generated anchors -->','','| name | position (m) | yaw | module | size |',
             '|---|---|---:|---|---|']
    for anchor in layout['anchors']:
        anchors.append('| '+anchor['name']+' | '+', '.join(f'{n:.3f}' for n in anchor['position'])+
            ' | '+str(anchor.get('yaw_degrees',''))+' | '+anchor.get('module','')+
            ' | '+str(anchor.get('size',''))+' |')
    readme=DOC/'README.md';text=readme.read_text().split('<!-- generated anchors -->')[0].rstrip()
    readme.write_text(text+'\n\n'+'\n'.join(anchors)+'\n')
    print(json.dumps({'passed':True,'files':len(FILES),'colours':colours,'plants':controls,'lighting':lighting},indent=2))


if __name__=='__main__':main()
