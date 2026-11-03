"""N3 signed white review media, GLB evidence, and explicit opening-view limits."""
from pathlib import Path
import hashlib
import json
import math
import re
import subprocess
import sys
import numpy as np
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/"output/culture-hall-323"
KIT=ROOT/"assets/rooms/poi_culture_hall";DEST=ROOT/"docs/design/poi-culture-hall-323-2026-11-03"
sys.path.insert(0,str(ROOT/"tools/art"))
from verify_chef_sign import load_glb,accessor
PREFIX="SGODOT-323_POI_CULTURE_HALL_WHITE_v0_"
font=lambda size:ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",size)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    plan=json.loads((KIT/"layout.json").read_text());stats=json.loads((KIT/"asset_stats.json").read_text())
    reports={k:json.loads((QA/v).read_text()) for k,v in {"plan":"plan-validation.json","navigation":"navigation.json","godot":"captures/validation.json"}.items()}
    assert all(v["passed"] for v in reports.values())
    for name in ["import.log","reimport.log","navigation.log","render.log"]:assert "ERROR:" not in (QA/name).read_text(),name
    assert reports["godot"]["triangles"]==stats["scene_triangles"] and len(reports["godot"]["seats"])==4
    subprocess.run(["git","diff","--exit-code","HEAD","--","assets/rooms/_shared/shell_hall","scenes/shell_hall"],cwd=ROOT,check=True)
    assert not (KIT/"props").exists()
    meshes=[];uids=set()
    for spec in plan["assets"]:
        path=KIT/spec["file"];doc,blob=load_glb(path);points=[];triangles=0;surfaces=0
        assert not doc.get("images") and not doc.get("textures")
        for mesh in doc["meshes"]:
            assert mesh["name"].endswith("_mobile")
            for primitive in mesh["primitives"]:
                points+=accessor(doc,blob,primitive["attributes"]["POSITION"])
                triangles+=len(accessor(doc,blob,primitive["indices"]))//3;surfaces+=1
        points=np.asarray(points);assert np.isfinite(points).all()
        lo,hi=points.min(0),points.max(0);natural=plan["models"].get(spec["name"],[1,1,1])
        assert np.allclose(hi-lo,natural,atol=.0001),(spec["name"],hi-lo,natural)
        assert abs(lo[1])<.0001 and triangles==spec["triangles"] and surfaces==spec["surfaces"]
        text=Path(str(path)+".import").read_text();uid=re.search(r'uid="(uid://[^\"]+)"',text).group(1)
        assert uid not in uids and "gltf/texture_map_mode=1" in text;uids.add(uid)
        meshes.append(dict(name=spec["name"],size_xyz=(hi-lo).tolist(),triangles=triangles,surfaces=surfaces,uid=uid,sha256=digest(path)))
    for path in (ROOT/"assets").rglob("*.import"):
        if path.parent==KIT:continue
        match=re.search(r'^uid="(uid://[^\"]+)"',path.read_text(),re.M)
        assert not match or match.group(1) not in uids,("UID collision",path)
    doc,blob=load_glb(ROOT/"assets/rooms/_shared/shell_hall/hall_back_wall.glb")
    points=np.concatenate([np.asarray(accessor(doc,blob,p["attributes"]["POSITION"])) for m in doc["meshes"] for p in m["primitives"]])
    skirting=float(points[points[:,1]<.30,2].max()-3.1)
    case=next(r for r in plan["placements"] if r["name"]=="glass_case_2")
    net=case["position"][2]-case["size"][2]/2-skirting;assert net>=2.0
    reports["actual_back_wall"]={"low_mesh_front_z":skirting,"net_clear_to_case2_m":net,"method":"Read actual shared back-wall vertices below local Y=.30 m"}
    reports["meshes"]=meshes;reports["stats"]=stats
    files=[]
    def raw(name):
        image=Image.open(QA/"captures"/(name+".png")).convert("RGB");assert np.asarray(image).std()>12;return image
    def save(image,name):
        path=DEST/(PREFIX+name+".png");meta=PngImagePlugin.PngInfo();meta.add_text("Author","ZHAOYUN / \u8d75\u4e91")
        meta.add_text("Description","SGODOT-323 white blockout / Godot Mobile Vulkan / approved layout proposal 1f4f9753")
        image.save(path,pnginfo=meta);assert path.stat().st_size<4_000_000;files.append(path)
    def caption(image,text):
        out=Image.new("RGB",(image.width,image.height+70),"#F3F6F6");out.paste(image,(0,0))
        ImageDraw.Draw(out).text((20,image.height+21),text,font=font(23),fill="#29454A");return out
    clean=raw("default_clean_720");assert clean.size==(720,1600);save(clean,"default_clean")
    marked=clean.copy();d=ImageDraw.Draw(marked)
    for y0,y1 in [(0,200),(1420,1600)]:d.rectangle((0,y0,719,y1),fill="#344E53")
    d.text((24,25),"CULTURE HALL | WHITE V0",font=font(29),fill="white")
    d.text((24,81),"43 deg / 45 deg / 6.72 m",font=font(26),fill="#D4E8E5")
    d.text((24,137),"HUD SAFE: 100 px at 360 width",font=font(24),fill="#D4E8E5")
    d.line((0,200,720,200),fill="#8CCCB9",width=3);d.line((0,1420,720,1420),fill="#8CCCB9",width=3)
    d.text((24,1450),"BAG SAFE: 90 px at 360 width",font=font(25),fill="#D4E8E5")
    d.text((24,1520),"SGODOT-323 | ZHAOYUN / \u8d75\u4e91",font=font(26),fill="white");save(marked,"default_43_safe")
    save(caption(raw("seated_overview"),"3 bench seats + 1 stool | native sit_idle / .715 m | ZHAOYUN / \u8d75\u4e91"),"four_seats")
    top=raw("topdown").convert("RGBA");overlay=Image.new("RGBA",top.size);d=ImageDraw.Draw(overlay)
    def xy(x,z):return (600+x*150,600+z*150)
    x0,z0,x1,z1=plan["rear_clear_band"];d.rectangle((*xy(x0,z0),*xy(x1,z1)),fill=(91,166,143,65),outline="#377E69",width=3)
    d.text(xy(.05,-2.00),"2.00 m CLEAR VIEWING STRIP",font=font(26),fill="#245C4F",anchor="mm")
    top=Image.alpha_composite(top,overlay).convert("RGB");d=ImageDraw.Draw(top)
    def arrow(a,b,label,color="#2C7382"):
        a,b=xy(*a),xy(*b);d.line([a,b],fill=color,width=3)
        dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);ux,uy=dx/length,dy/length
        d.polygon([b,(b[0]-ux*12-uy*5,b[1]-uy*12+ux*5),(b[0]-ux*12+uy*5,b[1]-uy*12-ux*5)],fill=color)
        if label:d.text(((a[0]+b[0])/2,(a[1]+b[1])/2-23),label,font=font(22),fill=color,anchor="mm",stroke_width=2,stroke_fill="white")
    for target in plan["review_targets"]:
        if target.get("direct"):arrow((plan["spawn"][0],plan["spawn"][2]),(target["position"][0],target["position"][2]),"")
    arrow((-2.35,.65),(-1.568,.65),".782 m")
    arrow((2.20,.912),(2.20,1.620),".708 m")
    for i,seat in enumerate([a for a in plan["anchors"] if a["name"].startswith("seat_")],1):
        x,y=xy(seat["position"][0],seat["position"][2]);d.ellipse((x-21,y-21,x+21,y+21),fill="#3D6879",outline="white",width=2)
        d.text((x,y),"S%d"%i,font=font(21),anchor="mm",fill="white")
    for name,label in [("glass_case_1","CASE 1"),("glass_case_2","CASE 2"),("display_plinth","PLINTH")]:
        row=next(r for r in plan["placements"] if r["name"]==name);at=xy(row["position"][0],row["position"][2])
        d.text(at,label,font=font(21),anchor="mm",fill="#29454A",stroke_width=2,stroke_fill="white")
    d.line([(90,65),(1110,65)],fill="#377E69",width=3);d.text((600,40),"6.80 m",font=font(25),anchor="mm",fill="#29454A")
    d.line([(60,120),(60,1080)],fill="#377E69",width=3);d.text((65,590),"6.40 m",font=font(25),fill="#29454A")
    save(caption(top,"4 seats / 16 positions | 3 direct entrance routes | net rear clearance 2.01 m | ZHAOYUN"),"topdown_ruler")
    image=raw("viewing_area_720");d=ImageDraw.Draw(image)
    d.rectangle((0,1420,719,1599),fill="#344E53")
    d.text((22,1445),"VIEWING AREA | NOT THE ENTRY SHOT",font=font(24),fill="white")
    d.text((22,1493),"Player [.65, .08, -1.70] | 43 deg / 6.72 m",font=font(23),fill="#D4E8E5")
    d.text((22,1540),"ZHAOYUN / \u8d75\u4e91",font=font(25),fill="white");save(image,"viewing_area_not_entry")
    on,off=np.asarray(raw("overview")).astype(float),np.asarray(raw("spots_off")).astype(float)
    reports["spotlight_control"]={"mean_abs_rgb255":float(np.abs(on-off).mean())};assert reports["spotlight_control"]["mean_abs_rgb255"]>.25
    reports.update(source_blend_sha256=digest(HERE/"culture_hall_blockout.blend"),layout_sha256=digest(KIT/"layout.json"),
        stage=json.loads((QA/"stage.json").read_text()),
        visual_review_pending="All six artworks are outside the native middle-entry opening view. No camera bias, spawn relocation or rear-floor filler was added. A clearly labelled same-scale viewing-area fixture is included for the art directors to decide the opening treatment.",
        scope="White layout review only; no Huangzhong final assets, atlas skin, Android/device, POI service or multiplayer acceptance.")
    (DEST/"validation-white-v0.json").write_text(json.dumps(reports,indent=2)+"\n")
    (DEST/"media-manifest-white-v0.json").write_text(json.dumps([dict(name=p.name,path=str(p.relative_to(ROOT)),sha256=digest(p),bytes=p.stat().st_size,mime="image/png",size=list(Image.open(p).size)) for p in files],indent=2)+"\n")
    print("CULTURE_PACKAGE",len(files),"images",stats["scene_triangles"],"triangles",stats["static_draw_surfaces"],"surfaces; rear net",net)
if __name__=="__main__":main()
