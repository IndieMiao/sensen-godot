"""Two signed Godot review images and the complete hardwood verification record."""
from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/hardwood-408';KIT=ROOT/'assets/farm/art'
DEST=ROOT/'docs/design/hardwood-grove-408-2026-11-04'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def main():
    a=json.loads((QA/'asset-validation.json').read_text());r=json.loads((QA/'render-validation.json').read_text())
    assert a['passed'] and r['passed'] and a['asset_sha256']==r['asset_sha256']==digest(KIT/'hardwood_grove.glb')
    for log in ['reimport.log','render.log']:assert 'ERROR:' not in (QA/log).read_text(),log
    rows=[]
    for source,name in [('pond','pond_L2_43'),('comparison','resource_comparison')]:
        im=Image.open(QA/(source+'.png')).convert('RGB');height=78 if source=='pond' else 100
        out=Image.new('RGB',(im.width,im.height+height),'#F3F2E6');out.paste(im,(0,0));d=ImageDraw.Draw(out)
        if source=='pond':
            d.text((10,im.height+7),'Hardwood · L2 (-0.3, -9.0) · 43°',font=font(18),fill='#39492D')
            d.text((10,im.height+32),'Fern Pond · 默认缩放 / 指定 goto 站位',font=font(17),fill='#39492D')
            d.text((10,im.height+56),'SGODOT-408 · 赵云 ZHAOYUN',font=font(16),fill='#39492D')
        else:
            for x,label in zip([196,665,1135,1604],['硬木林 Hardwood','原树林 Timber Grove','芦苇滩 Reed Bank','香草丛 Herb Patch']):
                d.text((x,im.height+16),label,font=font(25),fill='#39492D',anchor='mt')
            d.text((24,im.height+59),'同一塘内环境光与太阳 / 43° / 全部原生比例；硬木 1,042 面 · 1 surface · 赵云 ZHAOYUN',font=font(23),fill='#39492D')
        path=DEST/('SGODOT-408_HARDWOOD_v1_'+name+'.png');meta=PngImagePlugin.PngInfo()
        meta.add_text('Author','赵云 / ZHAOYUN');meta.add_text('Description','Godot Mobile Vulkan / original b1 pond lighting and default 43-degree zoom; comparison props at native scale. Caption appended outside the unedited screenshot.')
        out.save(path,pnginfo=meta);assert path.stat().st_size<4_000_000
        rows.append(dict(name=path.name,path=str(path.relative_to(ROOT)),sha256=digest(path),bytes=path.stat().st_size,mime='image/png',size=list(out.size)))
    report=dict(author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',assets=a,godot=r,
                stage=json.loads((QA/'stage.json').read_text()),source_blend_sha256=digest(HERE/'hardwood_grove.blend'),
                old_spot_source_sha256=digest(HERE/'reference/zz_spot_art_old.gd'),images=rows,
                scope='Hardwood asset only. Temporary local PondScenery insertion and scatter exclusion for review; no navigation/fishing/camera or gathered-state integration committed.')
    (DEST/'validation-v1.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    (DEST/'media-manifest-v1.json').write_text(json.dumps(rows,indent=2,ensure_ascii=False)+'\n')
    print('HARDWOOD_PACKAGE',len(rows),'images;',a['triangles'],'triangles',a['dimensions_m'])
if __name__=='__main__':main()
