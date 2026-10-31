"""Package signed prop review evidence from completed Godot captures."""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from dependencies import ROOT,SRC,OUT,write_json

DOC=ROOT/'docs/design/poi-service-hall-321-details-2026-10-31'
CAP=OUT/'details_captures'
KIT=ROOT/'assets/rooms/poi_service_hall'
PREFIX='SGODOT-321_N2_v1_props_'
AUTHOR='5281cd25-6a49-4df8-9802-f3e534956e80'
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'


def label(image,title,subtitle):
    font=ImageFont.truetype(FONT,13);heading=ImageFont.truetype(FONT,17 if image.width<500 else 25)
    probe=ImageDraw.Draw(image);lines=['']
    for letter in subtitle:
        if probe.textlength(lines[-1]+letter,font=font)>image.width-32:lines.append('')
        lines[-1]+=letter
    header=48+len(lines)*19
    result=Image.new('RGB',(image.width,image.height+header+36),'#f1f4f5');result.paste(image,(0,header))
    draw=ImageDraw.Draw(result);draw.text((16,8),title,font=heading,fill='#263e51')
    for i,line in enumerate(lines):draw.text((16,41+i*19),line,font=font,fill='#485b68')
    draw.text((16,result.height-27),'【黄忠】 SGODOT-321 / Godot Mobile / v1',font=font,fill='#485b68')
    return result


def main():
    DOC.mkdir(parents=True,exist_ok=True)
    geometry=json.loads((OUT/'details-geometry-validation.json').read_text())
    source=json.loads((OUT/'details-source-validation.json').read_text())
    godot=json.loads((CAP/'godot-validation.json').read_text())
    assert geometry['passed'] and source['passed'] and godot['passed']
    assert geometry['placed_prop_triangles']==godot['imported']['placed_prop_triangles']
    assert all((CAP/'godot-validation.json').stat().st_mtime>=p.stat().st_mtime for p in CAP.glob('*.png'))
    files=[];pixels=[]
    entries=[('props_overview','N2 / 新件总览','独立新件；角色 H=1.745m。未装配 B 座位，公共壳未换皮肤。'),
        ('sculpture_detail','N2 / 镂空螺旋雕塑','花环底座 Ø1.86m、高 0.40m；本体宽约 0.578m、高 1.20m；组合总高 1.60m。'),
        ('niche_displays','N2 / 双龛陈列','每龛宽 1.10m、顶高 2.40m、深 0.35m；展示台高 0.75m，贴墙框件。'),
        ('boards_and_service_props','N2 / 屏板与配套道具','叫号屏仅三色点；告示板四张空白纸；横匾留空；宣传架、饮水机和窗台花箱。'),
        ('fixed_props_default_43deg_360','N2 / 新件遮挡核对','43° / yaw 45° / 6.72m / 360px。仅固定新件，非整间定稿；壳仍为白模审阅色。'),
        ('fixed_props_overview','N2 / 固定新件全景','仅核对新件与原壳的尺度和挂墙关系；座位、地面皮肤与灯具不在本轮。')]
    for name,title,subtitle in entries:
        image=Image.open(CAP/(name+'.png')).convert('RGB')
        values=np.asarray(image);pixels.append({'image':name,'std':float(values.std()),'passed':bool(values.std()>15)})
        path=DOC/(PREFIX+name+'.png');label(image,title,subtitle).save(path);files.append(path)
    assert all(row['passed'] for row in pixels)
    validation={'author':'黄忠','virtual_user_id':AUTHOR,'passed':True,'geometry':geometry,'source':source,'godot':godot,'pixels':pixels,
        'scope':'Independent detailed props and fixed-object occlusion fixture. B room assembly awaits user approval. Desktop Vulkan Mobile only.',
        'mount_adjustments':{'brochure_rack_z_m':-2.55,'brochure_rack_forward_delta_m':.14,'notice_board_z_m':-2.83,
            'window_flowerbox_x_m':-2.91,'window_flowerbox_bottom_y_m':1.06,
            'reason':'Shared shell has protruding wainscot and window sill; avoid visible intersections without shell edits'}}
    path=DOC/(PREFIX+'validation.json');write_json(path,validation);files.append(path)
    rows=['# N2 独立新件实测表','', '| 模块 | 三角形 | surface | X × Y × Z (m) |', '|---|---:|---:|---|']
    for name,data in geometry['assets'].items():
        rows.append(f'| {name} | {data["triangles"]} | {data["surfaces"]} | '+' × '.join(f'{n:.4f}' for n in data['dimensions_m'])+' |')
    rows+=['',f'含第二只花箱：{geometry["placed_prop_triangles"]:,} 三角形 / {geometry["placed_prop_surfaces"]} surface。',
           '雕塑本体在底座上方 0.40m 处装配，总高 1.60m。挂墙板件使用中心轴心，其他件使用局部落地或安装轴心。',
           '所有网格从最终 GLB 顶点读取，单位 m；不是从设定图估尺寸。',
           '本轮仅独立新件，整间预算、座位挂点与胶囊在用户批准 B 后重新检查。']
    path=DOC/(PREFIX+'asset_table.md');path.write_text('\n'.join(rows)+'\n');files.append(path)
    media=[]
    for path in files:
        item={'file':path.name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'virtual_user_id':AUTHOR}
        if path.suffix=='.png':item['pixels']=list(Image.open(path).size)
        media.append(item)
    write_json(DOC/(PREFIX+'media-manifest.json'),media)
    print(json.dumps({'files':len(files),'triangles':geometry['placed_prop_triangles'],'occlusion':godot['occlusion']}))


if __name__=='__main__':main()
