"""Package original Godot captures with signatures outside the game image."""
from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/plaque-401'
DEST=ROOT/'docs/design/upgrade-plaque-401-2026-11-04';KIT=ROOT/'assets/farm/art'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def font(n):return ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
def main():
    assets=json.loads((QA/'asset-validation.json').read_text());render=json.loads((QA/'render-validation.json').read_text())
    assert assets['passed'] and render['passed'] and assets['asset_sha256']==render['asset_sha256']==digest(KIT/'upgrade_plaque.glb')
    for log in ['reimport.log','render.log']:
        assert 'ERROR:' not in (QA/log).read_text(),log
    rows=[]
    for source,name in [('default','default_43'),('two_signs','paired_signs')]:
        image=Image.open(QA/(source+'.png')).convert('RGB')
        size=image.size
        pad=72 if image.width<700 else 90
        out=Image.new('RGB',(image.width,image.height+pad),'#F5F2E8');out.paste(image,(0,0));d=ImageDraw.Draw(out)
        if source=='default':
            d.text((12,image.height+8),'SGODOT-401 · Upgrade Plaque · v1',font=font(18),fill='#3B4A36')
            d.text((12,image.height+33),'b1 原生默认 43° / Lv3 · 赵云 ZHAOYUN',font=font(17),fill='#3B4A36')
        else:
            d.text((24,image.height+10),'左：B 案升级木牌 ×1.0 / 0.50×0.70 m　右：原门牌 ×0.8 / 高约0.612 m',font=font(25),fill='#3B4A36')
            d.text((24,image.height+49),'日期为运行时 Label3D 示例，GLB 牌面完全空白 · 486 三角面 / 1 surface · 赵云 ZHAOYUN',font=font(23),fill='#3B4A36')
        path=DEST/('SGODOT-401_UPGRADE_PLAQUE_v1_'+name+'.png');meta=PngImagePlugin.PngInfo()
        meta.add_text('Author','赵云 / ZHAOYUN');meta.add_text('Description','Godot Mobile Vulkan; actual copied b1 farm. Original native screenshot with external signature footer; no image colour correction.')
        out.save(path,pnginfo=meta)
        rows.append(dict(name=path.name,path=str(path.relative_to(ROOT)),sha256=digest(path),bytes=path.stat().st_size,mime='image/png',size=list(out.size),native_image_size=list(size)))
    report=dict(author='赵云',virtual_user_id='8ea32e40-c0ba-4a31-864f-374a6bcbc554',assets=assets,godot=render,
                stage=json.loads((QA/'stage.json').read_text()),source_blend_sha256=digest(HERE/'upgrade_plaque.blend'),
                integration_note='Review-only substitution in an isolated b1 copy, retained PLAQUE_CELL and .35 rad rotation. No game scene changes committed. Use PackedScene to retain PlaqueText; FarmArt.instance extracts only mesh.',
                bounds_note='Origin is the centre of the post footprint at Y=0. Header/face project toward +Z, so full object Z bounds are asymmetric.',
                camera_note='b1 native Lv3 opening fits the 12 open beds at 43 degrees, effective width about 10.927 m. Close-up is separate, 43 degrees / 4m width; full default camera retained.',images=rows)
    (DEST/'validation-v1.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    (DEST/'media-manifest-v1.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
    print('PLAQUE_PACKAGE',len(rows),'images;',assets['triangles'],'triangles;',assets['uid'])
if __name__=='__main__':main()
