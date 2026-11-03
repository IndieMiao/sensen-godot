"""Signed independent-subset images; display assets are explicitly still proxies."""
from pathlib import Path
import hashlib
import json
import re
import numpy as np
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/"output/culture-hall-323"
KIT=ROOT/"assets/rooms/poi_culture_hall";DEST=ROOT/"docs/design/poi-culture-hall-323-2026-11-03"
PREFIX="SGODOT-323_POI_CULTURE_HALL_REUSE_v0_"
font=lambda size:ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",size)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    stats=json.loads((KIT/"asset_stats.json").read_text());plan=json.loads((KIT/"layout.json").read_text())
    reports={key:json.loads((QA/name).read_text()) for key,name in {"plan":"plan-validation.json","navigation":"navigation.json","assets":"reuse-assets.json","godot":"captures/validation.json"}.items()}
    assert all(r["passed"] for r in reports.values())
    for name in ["import-reuse.log","reimport-reuse.log","navigation-reuse.log","render-reuse.log"]:assert "ERROR:" not in (QA/name).read_text(),name
    baseline=json.loads((DEST/"validation-white-v0.json").read_text())
    assert reports["godot"]["native_camera"]==baseline["godot"]["native_camera"]
    assert reports["godot"]["triangles"]==stats["scene_triangles"] and len(reports["godot"]["seats"])==4
    uids={}
    for asset in plan["assets"]:
        text=(KIT/(asset["file"]+".import")).read_text();uid=re.search(r'uid="(uid://[^\"]+)"',text).group(1)
        assert uid not in uids.values() and "gltf/texture_map_mode=1" in text;uids[asset["file"]]=uid
    for path in (ROOT/"assets").rglob("*.import"):
        if path.parent==KIT:continue
        match=re.search(r'^uid="(uid://[^\"]+)"',path.read_text(),re.M)
        assert not match or match.group(1) not in uids.values(),path
    files=[]
    def raw(name):
        image=Image.open(QA/"captures"/(name+".png")).convert("RGB");assert np.asarray(image).std()>12;return image
    def save(image,name):
        path=DEST/(PREFIX+name+".png");meta=PngImagePlugin.PngInfo();meta.add_text("Author","ZHAOYUN / \u8d75\u4e91")
        meta.add_text("Description","SGODOT-323 independent reuse preassembly; display cases/art/exhibits/mosaic/sign remain approved gray proxies")
        image.save(path,pnginfo=meta);assert path.stat().st_size<4_000_000;files.append(path)
    def caption(image,text):
        out=Image.new("RGB",(image.width,image.height+70),"#F4F6F5");out.paste(image,(0,0))
        ImageDraw.Draw(out).text((20,image.height+22),text,font=font(22),fill="#294148");return out
    default=raw("default_clean_720");save(default,"default_clean")
    viewing=raw("viewing_area_720");d=ImageDraw.Draw(viewing);d.rectangle((0,1420,719,1599),fill="#344E53")
    d.text((22,1445),"VIEWING AREA | REUSE PREASSEMBLY",font=font(25),fill="white")
    d.text((22,1495),"43 deg / 6.72 m | Display props pending",font=font(24),fill="#D4E8E5")
    d.text((22,1543),"ZHAOYUN / \u8d75\u4e91",font=font(25),fill="white");save(viewing,"viewing_area")
    save(caption(raw("overview"),"Reuse subset / gray display proxies | %s triangles / %s surfaces | ZHAOYUN"%(stats["scene_triangles"],stats["static_draw_surfaces"])),"overview")
    save(caption(raw("seated_overview"),"4 native sit_idle poses | approved .715 m seat surface | ZHAOYUN / \u8d75\u4e91"),"four_seats")
    save(caption(raw("seating_plant_detail"),"Reused bench / stool / Monstera | one atlas, alpha scissor .45 | ZHAOYUN"),"seating_plant_detail")
    save(caption(raw("track_detail"),"One track / three heads | gray artwork proxies unchanged | ZHAOYUN"),"track_detail")
    off=raw("wall_lights_off");pair=Image.new("RGB",(1440,1600));pair.paste(off,(0,0));pair.paste(default,(720,0))
    save(caption(pair,"Wall lights OFF / ON | same camera, sun, environment and track spots | ZHAOYUN"),"wall_lights")
    delta=float(np.abs(np.asarray(default).astype(float)-np.asarray(off)).mean());assert delta>.25
    detail=raw("seating_plant_detail");samples=[detail.getpixel(p) for p in [(700,220),(650,280),(550,350),(730,300)]]
    reports.update(stats=stats,import_uids=uids,source_blend_sha256=digest(HERE/"culture_hall_reuse.blend"),
        layout_sha256=digest(KIT/"layout.json"),atlas_sha256=digest(KIT/"room_albedo_ao.png"),
        stage=json.loads((QA/"stage.json").read_text()),wall_lights_mean_abs_rgb255=delta,
        bench_shaded_samples_rgb=samples,reference_accent_srgb="465823",
        opening_approved="95aed0c2 / 1eb4f28b: unchanged opening; all six paintings are intentionally seen only from inside the viewing area.",
        scope="Independent shell skin, seats, lighting and Monstera only. No final Huangzhong display files, full-room completion, Android or service integration claimed.")
    (DEST/"validation-reuse-v0.json").write_text(json.dumps(reports,indent=2)+"\n")
    (DEST/"media-manifest-reuse-v0.json").write_text(json.dumps([dict(name=p.name,path=str(p.relative_to(ROOT)),sha256=digest(p),bytes=p.stat().st_size,mime="image/png",size=list(Image.open(p).size)) for p in files],indent=2)+"\n")
    print("CULTURE_REUSE_PACKAGE",len(files),"images; bench samples",samples,"wall light delta",delta)
if __name__=="__main__":main()
