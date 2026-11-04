"""Sign actual b1 captures; measure the difference from the matching digit-off controls."""
from pathlib import Path
import hashlib, json
import numpy as np
from PIL import Image, ImageDraw, ImageFont, PngImagePlugin
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[3]; QA=ROOT/'output/badge-401'
DEST=ROOT/'docs/design/homestead-badge-401-2026-11-04'
BG='#F7F2E7'; INK='#3B2F25'; MARK='#13776C'
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    assets=json.loads((QA/'asset-validation.json').read_text()); render=json.loads((QA/'render-validation.json').read_text())
    assert assets['passed'] and render['passed']
    assert assets['asset_sha256']==render['asset_sha256']==digest(ROOT/'assets/farm/art/homestead_badge.glb')
    assert render['renderer']=='mobile'
    assert all('ERROR:' not in (QA/log).read_text() for log in ['render.log','reimport.log'])
    media=[]; pixels=[]
    def save(image, suffix, note):
        path=DEST/('SGODOT-401_HOMESTEAD_BADGE_v1_'+suffix+'.png')
        meta=PngImagePlugin.PngInfo();meta.add_text('Author','赵云 / ZHAOYUN')
        meta.add_text('Description',note+' Godot Mobile/Vulkan; real isolated b1 farm. No image colour correction.')
        image.save(path,pnginfo=meta)
        media.append(dict(name=path.name,path=str(path.relative_to(ROOT)),sha256=digest(path),bytes=path.stat().st_size,mime='image/png',size=list(image.size)))
    for row in render['tiers']:
        level=row['level']; src=Image.open(QA/f'follow_{level}.png').convert('RGB')
        control=Image.open(QA/f'control_no_digits_{level}.png').convert('RGB')
        a=np.array(src).astype(int); b=np.array(control).astype(int)
        scale=src.width/360; cx,cy=row['number_centre']
        x0,x1=int((cx-18)*scale),int((cx+18)*scale)
        y0,y1=int((cy-12)*scale),int((cy+18)*scale)
        delta=np.max(np.abs(a-b),axis=2)[y0:y1,x0:x1]
        yy,xx=np.where(delta>35)
        bounds=[int(xx.min()+x0),int(yy.min()+y0),int(xx.max()+x0+1),int(yy.max()+y0+1)]
        cap=(bounds[3]-bounds[1])/scale
        diameter=float(np.linalg.norm(np.array(row['disc_right'])-row['disc_left']))
        assert cap>=14 and diameter>=32 and bounds[2]-bounds[0]<.62*360/6.72*scale
        pixels.append(dict(level=level,diameter_logical_px=diameter,digit_cap_logical_px=cap,digit_ink_physical_bounds=bounds,
            logical_width=360,physical_scale=scale,threshold_rgb_delta=35,source_sha256=digest(QA/f'follow_{level}.png'),control_sha256=digest(QA/f'control_no_digits_{level}.png')))
        out=Image.new('RGB',(760,900),BG); out.paste(src.resize((360,800)),(0,60)); d=ImageDraw.Draw(out)
        d.text((18,13),f'家园徽章 · Lv{level} / {row["tier"]} · 跟随镜头 zoom 1',font=font(22),fill=INK)
        # The left game view is untouched at 360 logical pixels. The right panel is labelled enlargement only.
        crop_box=(int(cx-28),int(cy-27),int(cx+28),int(cy+42))
        crop=src.crop(tuple(round(v*scale) for v in crop_box)).resize((280,345),Image.Resampling.NEAREST)
        out.paste(crop,(414,112))
        d.text((389,76),'局部放大 ×5（左侧为原尺寸实拍）',font=font(17),fill=INK)
        lx=414+(row['disc_left'][0]-crop_box[0])*5
        rx=414+(row['disc_right'][0]-crop_box[0])*5
        y=119
        d.line((lx,y,rx,y),fill=MARK,width=2)
        for x in [lx,rx]:d.line((x,y-5,x,y+5),fill=MARK,width=2)
        d.text((419,465),f'圆章 Ø {diameter:.1f} px / 0.80 m',font=font(21),fill=MARK)
        bx=414+(bounds[2]/scale-crop_box[0])*5+10
        top=112+(bounds[1]/scale-crop_box[1])*5;bottom=112+(bounds[3]/scale-crop_box[1])*5
        d.line((bx,top,bx,bottom),fill=MARK,width=2)
        for y in [top,bottom]:d.line((bx-5,y,bx+5,y),fill=MARK,width=2)
        d.text((419,502),f'数字 cap {cap:.0f} px（最低 14 px）',font=font(21),fill=MARK)
        notes=['口径：360 宽逻辑像素','43° / 6.72 m / 原生跟随相机','数字：Nunito ExtraBold Label3D','关数字对照相减，测实际墨迹高度','模型面底空白；颜色 #3B2F25','896 面（全文件）/ 332 面（显示一档）','2 个可见 surface / 1 个哑光材质']
        for k,note in enumerate(notes):d.text((390,558+k*31),note,font=font(17),fill=INK)
        d.text((18,867),'SGODOT-401 · C63 A · b1 农场实渲 / Mobile Vulkan · 赵云 ZHAOYUN',font=font(17),fill=INK)
        save(out,f'follow_Lv{level}', 'Left: untouched 360x800 native follow view. Right: nearest-neighbour labelled crop and measured cap height.')
    src=Image.open(QA/'four_tiers.png').convert('RGB')
    out=Image.new('RGB',(1600,940),BG);out.paste(src,(0,0));d=ImageDraw.Draw(out)
    for x,name in zip([270,623,977,1330],['Lv3 · wood / 木','Lv7 · bronze / 铜','Lv10 · silver / 银','Lv17 · gold / 金']):
        d.text((x,836),name,font=font(27),fill=INK,anchor='mt')
    d.text((30,892),'同一 b1 农场、原灯光；43° 近景 / 数字为运行时 Label3D / 四档同时摆放仅用于比较 · 赵云 ZHAOYUN',font=font(23),fill=INK)
    save(out,'four_tiers_close','Four models in the same farm World3D, same lighting; comparison-only close camera.')
    out=Image.new('RGB',(1440,910),BG);d=ImageDraw.Draw(out)
    for i,level in enumerate([3,7,10,17]):
        src=Image.open(QA/f'opening_{level}.png').convert('RGB').resize((360,800))
        out.paste(src,(i*360,56));d.text((i*360+16,12),f'Lv{level} · {render["tiers"][i]["tier"]}',font=font(24),fill=INK)
    d.text((20,869),'开场全景：四档同机位 / 原生 Lv3 农场开场自动放宽，仅比较档位色；字高验收见跟随镜头 · 赵云 ZHAOYUN',font=font(21),fill=INK)
    save(out,'opening_tier_comparison','Four untouched opening views placed side by side; only tier appearance changes, fixture farm remains Lv3 for identical framing.')
    report=dict(author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',assets=assets,godot=render,pixels=pixels,
        stage=json.loads((QA/'stage.json').read_text()),source_blend_sha256=digest(HERE/'homestead_badge.blend'),images=media,
        budget_note='896 triangles includes all four hidden/visible tiers. Five stored mesh surfaces, two simultaneously visible (common base + one selected tier); one material. Label3D cost excluded from asset mesh budget.',
        scope='Only new art, import hook, manifest append and review sources are committed. Game fixture and scene substitution stay under output; no b1 integration or save changes.')
    (DEST/'validation-v1.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    (DEST/'media-manifest-v1.json').write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
    print('BADGE_PACKAGE',len(media),'images;', [(p['level'],p['digit_cap_logical_px']) for p in pixels])
if __name__=='__main__':main()
