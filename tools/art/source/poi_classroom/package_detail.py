"""Package inspected Godot screenshots, source hashes and actual validation."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/"output/classroom-322"
KIT=ROOT/"assets/rooms/poi_classroom";DEST=ROOT/"docs/design/poi-classroom-322-2026-11-03"
PREFIX="SGODOT-322_POI_CLASSROOM_v1_"
FONT="/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
font=lambda size:ImageFont.truetype(FONT,size)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    plan=json.loads((KIT/"layout.json").read_text());stats=json.loads((KIT/"asset_stats.json").read_text())
    reports={key:json.loads((QA/name).read_text()) for key,name in {
        "plan":"plan-validation.json","navigation":"navigation.json","assets":"detail-assets.json","godot":"captures/validation.json"}.items()}
    assert all(r["passed"] for r in reports.values())
    for name in ["navigation.log","render.log","import-detail.log","reimport-detail.log"]:
        assert "ERROR:" not in (QA/name).read_text(),name
    assert reports["godot"]["triangles"]==stats["scene_triangles"]
    assert len(reports["godot"]["seats"])==6
    files=[]
    def raw(name):
        image=Image.open(QA/"captures"/(name+".png")).convert("RGB")
        assert np.asarray(image).std()>12,name
        return image
    def save(image,name):
        path=DEST/(PREFIX+name+".png");metadata=PngImagePlugin.PngInfo()
        metadata.add_text("Author","ZHAOYUN / \u8d75\u4e91")
        metadata.add_text("Description","SGODOT-322 detail v1 / Godot Mobile Vulkan / 317 R3 / camera contract in README")
        image.save(path,pnginfo=metadata);assert path.stat().st_size<4_000_000
        files.append(path)
    def captioned(image,text):
        sheet=Image.new("RGB",(image.width,image.height+70),"#F4F6F6");sheet.paste(image,(0,0))
        ImageDraw.Draw(sheet).text((20,image.height+20),text,font=font(23),fill="#283A3D")
        return sheet
    clean=raw("default_clean_720");assert clean.size==(720,1600)
    save(clean,"default_clean")
    marked=clean.copy();d=ImageDraw.Draw(marked)
    for y0,y1 in [(0,200),(1420,1600)]:d.rectangle((0,y0,719,y1),fill="#344D50")
    d.line((0,200,720,200),fill="#79C6B1",width=3);d.line((0,1420,720,1420),fill="#79C6B1",width=3)
    d.text((24,26),"CLASSROOM | V1",font=font(30),fill="white")
    d.text((24,81),"43 deg / 45 deg / 6.72 m",font=font(26),fill="#D9E7E1")
    d.text((24,135),"HUD SAFE: 100 px at 360 width",font=font(24),fill="#D9E7E1")
    d.text((24,1444),"BACKPACK SAFE: 90 px at 360 width",font=font(24),fill="#D9E7E1")
    d.text((24,1510),"SGODOT-322 | ZHAOYUN / \u8d75\u4e91",font=font(26),fill="white")
    save(marked,"default_safe")
    save(captioned(raw("overview"),"43 deg full room | %s triangles / %s surfaces | ZHAOYUN"%(stats["scene_triangles"],stats["static_draw_surfaces"])),"overview")
    save(captioned(raw("seated_overview"),"6 native sit_idle poses | seat top .715 m | ZHAOYUN / \u8d75\u4e91"),"six_seats")
    top=raw("topdown");d=ImageDraw.Draw(top)
    def xy(x,z):return (600+x*150,600+z*150)
    for a in plan["anchors"]:
        if a["name"].startswith("seat_"):
            x,y=xy(a["position"][0],a["position"][2]);d.ellipse((x-20,y-20,x+20,y+20),fill="#386D70",outline="white",width=2)
            d.text((x,y),"S"+a["name"][-1],anchor="mm",font=font(20),fill="white")
    for a,b,label in [((-.04,.30),(1.09,.30),"1.13 m"),((-1.80,-.73),(-1.06,-.73),".74 m"),((2.11,.3),(3.34,.3),"1.23 m"),((.5,-2.0185),(.5,-1.24),".779 m")]:
        a,b=xy(*a),xy(*b);d.line([a,b],fill="#267F8A",width=3)
        d.text(((a[0]+b[0])/2,(a[1]+b[1])/2-18),label,anchor="mm",font=font(22),fill="#226671",stroke_width=2,stroke_fill="white")
    d.line([(90,55),(1110,55)],fill="#267F8A",width=3);d.text((600,34),"6.80 m",font=font(23),anchor="mm",fill="#226671")
    d.line([(55,120),(55,1080)],fill="#267F8A",width=3);d.text((63,600),"6.40 m",font=font(23),fill="#226671")
    save(captioned(top,"6 seats / 16 standing positions | capsule .25 m / main aisle .35 m | ZHAOYUN"),"topdown_ruler")
    ref=Image.open(HERE/"reference/SGODOT-317_Classroom_Main_2026-10-31.png").convert("RGB")
    render=raw("reference_view");assert ref.size==render.size
    sheet=Image.new("RGB",(ref.width*2,ref.height+116),"#F4F6F6");sheet.paste(ref,(0,0));sheet.paste(render,(ref.width,0));d=ImageDraw.Draw(sheet)
    d.text((24,ref.height+16),"Stark | SGODOT-317 R3",font=font(28),fill="#283A3D")
    d.text((ref.width+24,ref.height+16),"Godot | matched yaw / estimated 35 deg reference pitch",font=font(27),fill="#283A3D")
    d.text((24,ref.height+68),"Reference-camera estimate from roof edges; default game camera remains 43 deg. ZHAOYUN / \u8d75\u4e91",font=font(25),fill="#283A3D")
    save(sheet,"stark_comparison")
    for name in ["reading_detail","teaching_detail"]:save(captioned(raw(name),"SGODOT-322 | "+name.replace("_"," ")+" | ZHAOYUN / \u8d75\u4e91"),name)
    for name,left,right,label in [
        ("local_lights","local_lights_off","default_clean_720","Local lights OFF / ON (same sun, environment and camera)"),
        ("clip_comparison","default_native_clip_720","default_clean_720","Legacy far=4000 / hall far=40 (same framing; integration note)")]:
        a,b=raw(left),raw(right);diff=float(np.abs(np.asarray(a).astype(float)-np.asarray(b)).mean())
        assert diff>1,(name,diff)
        pair=Image.new("RGB",(1440,1600));pair.paste(a,(0,0));pair.paste(b,(720,0))
        save(captioned(pair,label+" | ZHAOYUN"),name)
        reports[name]={"mean_abs_rgb255":diff,"left":left,"right":right}
    reports.update(stage=json.loads((QA/"stage.json").read_text()),stats=stats,
        source_blend_sha256=digest(HERE/"classroom_detail.blend"),layout_sha256=digest(KIT/"layout.json"),
        camera_note="Original P0 frame_all projection and spawn; review applies hall near=.1/far=40 from layout. Legacy P0 ignores these and uses far=4000; clip control is included. No consumer runtime code changed.",
        scope="Desktop Mobile/Vulkan art review. No Android, physical phone, multiplayer/service integration or release.")
    (DEST/"validation-v1.json").write_text(json.dumps(reports,indent=2)+"\n")
    (DEST/"media-manifest-v1.json").write_text(json.dumps([dict(name=p.name,path=str(p.relative_to(ROOT)),sha256=digest(p),bytes=p.stat().st_size,mime="image/png",size=list(Image.open(p).size)) for p in files],indent=2)+"\n")
    print("CLASSROOM_V1_PACKAGE",len(files),"images",stats["scene_triangles"],"triangles",stats["static_draw_surfaces"],"surfaces")

if __name__=="__main__":main()
