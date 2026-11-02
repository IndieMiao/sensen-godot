"""Package signed Godot blockout evidence and verify immutable dependencies."""
from pathlib import Path
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont,ImageOps
from dependencies import ROOT,SRC,OUT,DEPS,write_json

DOC=ROOT/'docs/design/poi-service-hall-321-blockout-2026-10-31'
DOC.mkdir(parents=True,exist_ok=True)
CAP=OUT/'captures'
PREFIX='SGODOT-321_N2_blockout_'
FONTS={size:ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',size) for size in [13,17,21,25,30]}
AUTHOR='5281cd25-6a49-4df8-9802-f3e534956e80'
MEDIA=[]


def labelled(image,title,subtitle):
    probe=ImageDraw.Draw(image);lines=['']
    for ch in subtitle:
        if probe.textlength(lines[-1]+ch,font=FONTS[13])>image.width-32:lines.append('')
        lines[-1]+=ch
    header=42+19*len(lines)
    canvas=Image.new('RGB',(image.width,image.height+header+34),'#f0f3f2');canvas.paste(image,(0,header))
    draw=ImageDraw.Draw(canvas);draw.text((16,5),title,font=FONTS[17 if image.width<500 else 25],fill='#253e46')
    for i,line in enumerate(lines):draw.text((16,34+i*19),line,font=FONTS[13],fill='#4a6269')
    draw.text((16,canvas.height-27),'【黄忠】 SGODOT-321 / N2 BLOCKOUT',font=FONTS[13],fill='#344e53')
    return canvas


def save(image,name):
    path=DOC/(PREFIX+name+'.png');image.save(path);MEDIA.append(path)


def main():
    layouts=json.loads((SRC/'blockout_layouts.json').read_text())
    godot=json.loads((CAP/'godot-validation.json').read_text())
    assert godot['passed'],godot['failures']
    budgets=json.loads((CAP/'budget-validation.json').read_text());assert budgets['passed']
    manifest=json.loads((SRC/'dependency_manifest.json').read_text())
    checked=[]
    for dependency in manifest['dependencies']:
        for source in dependency['files']:
            assert hashlib.sha256((DEPS/source['path']).read_bytes()).hexdigest()==source['sha256'],source['path']
            staged=OUT/'project'/source['path']
            if staged.exists() and staged.suffix in ['.glb','.gd','.tscn','.json','.png']:
                assert hashlib.sha256(staged.read_bytes()).hexdigest()==source['sha256'],source['path']
            checked.append({'path':source['path'],'commit':dependency['commit'],'unchanged':True})
    titles={'A1':'原件 11 座','A2':'窄件 11 座','B':'原件 8 座 / 推荐'}
    captions={'A1':'1 张小圆桌、2 盆植物；去掉 2 张边桌和 2 盆植物。',
              'A2':'3 张小圆桌、2 盆植物；沙发 2.30m、扶手椅 1.30m，仅 X 向白模缩放。',
              'B':'3 张小圆桌、4 盆植物；减少 3 把扶手椅，保留左右候客组与展示墙。'}
    overview=[]
    for plan in layouts['layouts']:
        name=plan['id'];minimum=plan['clearance']['main_min_m']
        default=Image.open(CAP/(name+'_default_43deg_360.png')).convert('RGB')
        save(labelled(default,name+' / '+titles[name],f'43° / 6.72m / H=1.745m；主路最窄 {minimum:.2f}m。 '+captions[name]),name+'_default_43deg_360')
        image=Image.open(CAP/(name+'_overview_43deg.png')).convert('RGB')
        save(labelled(image,name+' / '+titles[name],f'全景另行缩远；环道 {minimum:.2f}m，入口 {plan["clearance"]["entry_min_m"]:.2f}m。 '+captions[name]),name+'_overview_43deg')
        overview.append((name,ImageOps.contain(image,(600,500),Image.Resampling.LANCZOS)))
        top=Image.open(CAP/(name+'_top_capsule.png')).convert('RGB');draw=ImageDraw.Draw(top)
        capture=next(c for c in godot['captures'] if c['id']==name+'_top_capsule')
        for i,seat in enumerate(capture['seat_screen_points']):
            x,y=seat['position'];draw.ellipse((x-14,y-14,x+14,y+14),fill='#f7e0a9',outline='#855e28',width=2)
            label=str(i+1);width=draw.textlength(label,font=FONTS[17]);draw.text((x-width/2,y-13),label,font=FONTS[17],fill='#553b17')
        x,y=capture['minimum_label_px'];text=f'{minimum:.2f} m'
        bounds=draw.textbbox((x+14,y-18),text,font=FONTS[21]);draw.rectangle((bounds[0]-5,bounds[1]-3,bounds[2]+5,bounds[3]+3),fill='#fff4da')
        draw.text((x+14,y-18),text,font=FONTS[21],fill='#9b4f21')
        save(labelled(top,name+f' / {plan["seat_count"]} 座 / 主路最窄 {minimum:.2f}m','黄号：座位；绿线：标准胶囊路径；蓝圈：16 个可达站位；橙线：最窄净距。 '+captions[name]),name+'_top_capsule')
    sheet=Image.new('RGB',(1800,555),'#f0f3f2');draw=ImageDraw.Draw(sheet)
    for i,(name,image) in enumerate(overview):
        sheet.paste(image,(i*600,50));draw.text((i*600+18,8),name+' / '+titles[name],font=FONTS[25],fill='#253e46')
    save(labelled(sheet,'N2 服务大厅 / 三版白模','公共壳原文件不改；坐面相对地面 0.715m，世界 Y=0.795m；排法确认前不做细模。'),'comparison')
    validation={'task':'SGODOT-321','author':'黄忠','virtual_user_id':AUTHOR,'passed':True,
                'geometry_and_routes':layouts,'godot':godot,'blockout_budgets':budgets,'unchanged_dependencies':checked,
                'narrowing_assessment':json.loads((SRC/'narrowing_assessment.json').read_text()),
                'scope':'Offline neutral blockouts; no final skin, detailed new art, gameplay integration, or merge approval.'}
    path=DOC/(PREFIX+'validation.json');write_json(path,validation);MEDIA.append(path)
    decision=['# N2 白模决策表','', '| 方案 | 座位 | 坐具宽度 | 小圆桌 / 植物 | 最窄环道 | 入口净宽 |',
              '|---|---:|---|---|---:|---:|']
    for plan in layouts['layouts']:
        tables=sum(p['asset']=='small_round_table' for p in plan['items']);plants=sum(p['asset']=='peace_lily' for p in plan['items'])
        decision.append(f'| {plan["id"]} | {plan["seat_count"]} | '+('沙发 2.30m / 椅 1.30m' if plan['id']=='A2' else '沙发 2.806m / 椅 1.50m')+f' | {tables} / {plants} | {plan["clearance"]["ring_min_m"]:.2f}m | {plan["clearance"]["entry_min_m"]:.2f}m |')
    decision+=['','推荐 B：左右各一组沙发加单椅，展示墙前方清楚，十字主路更宽。若 11 座优先，A2 比 A1 更从容，但需要源件改比例。',
               'A1 去掉两张边桌、两盆植物；A2 去掉两盆植物；B 去掉三把扶手椅。保留的小桌均为 Ø0.60m、高 0.75m 白模。',
               '所有方案通过真实 Godot 胶囊扫掠与 16 个可达站位检查。盆栽按 Ø0.49m、高 0.39m 的实际盆体碰撞，叶片不设硬碰撞。',
               'A2 节点 X 缩放仅为已获总监许可的白模占位。细模需重做源比例、圆角和卷边；沙发三片坐垫合计约 2.10m，扶手椅坐垫保留 0.99m，Y/Z 和座高不变。',
               '蓝色十字与环形走道由地面材质区显示，没有新增凸起地毯网格。雕塑与展示龛等新件仅表示派活尺寸的体积。',
               '实际公共壳地面 Y=0.08m，所以座位挂点 Y=0.795m，离地仍是 0.715m。原壳及 324 文件使用固定提交并校验哈希。']
    path=DOC/(PREFIX+'decision.md');path.write_text('\n'.join(decision)+'\n');MEDIA.append(path)
    records=[]
    for path in MEDIA:
        row={'file':path.name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'virtual_user_id':AUTHOR}
        if path.suffix=='.png':row['pixels']=list(Image.open(path).size)
        records.append(row)
    write_json(DOC/(PREFIX+'media-manifest.json'),records)
    print('N2_PACKAGED',len(records),'files',len(godot['checks']),'checks')


if __name__=='__main__':main()
