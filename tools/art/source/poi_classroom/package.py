"""Signed white-model review images and reproducible asset/navigation evidence."""
from pathlib import Path
import hashlib
import json
import math
import struct
import subprocess

import numpy as np
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/"output/classroom-322"
KIT=ROOT/"assets/rooms/poi_classroom";DEST=ROOT/"docs/design/poi-classroom-322-2026-11-03"
PREFIX="SGODOT-322_POI_CLASSROOM_WHITE_v0_"
FONT="/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
font=lambda size:ImageFont.truetype(FONT,size)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    plan=json.loads((KIT/"layout.json").read_text())
    planar=json.loads((QA/"plan-validation.json").read_text())
    navigation=json.loads((QA/"navigation.json").read_text())
    render=json.loads((QA/"captures/validation.json").read_text())
    assert planar["passed"] and navigation["passed"] and render["passed"]
    for name in ["navigation.log","render.log"]:
        assert "ERROR:" not in (QA/name).read_text(),name
    assert len(render["seats"])==6 and all(s["animation"]=="sit_idle" for s in render["seats"])
    subprocess.run(["git","diff","--exit-code","--","assets/rooms/_shared/shell_hall","scenes/shell_hall"],cwd=ROOT,check=True)
    expected={"blockout_student_desk":[1.02,1.745*.65,.58],"blockout_student_stool":[.48,.715,.48],
              "blockout_box":[1,1,1],"blockout_cylinder":[1,1,1],"blockout_ball":[1,1,1]}
    glbs=[]
    for name,size in expected.items():
        path=KIT/(name+".glb");raw=path.read_bytes();length=struct.unpack_from("<I",raw,12)[0]
        doc=json.loads(raw[20:20+length]);p=doc["meshes"][0]["primitives"][0]
        assert len(doc["meshes"])==1 and len(doc["meshes"][0]["primitives"])==1
        assert doc["meshes"][0]["name"]==name+"_mobile"
        bounds=doc["accessors"][p["attributes"]["POSITION"]]
        measured=np.array(bounds["max"])-np.array(bounds["min"])
        assert np.allclose(measured,size,atol=.0001),(name,measured,size)
        assert abs(bounds["min"][1])<.0001
        assert not doc.get("images") and not doc.get("textures")
        glbs.append({"name":name,"triangles":doc["accessors"][p["indices"]]["count"]//3,"size_xyz":measured.tolist(),"sha256":digest(path)})
    DEST.mkdir(parents=True,exist_ok=True);files=[]
    def save(image,name):
        path=DEST/(PREFIX+name+".png");metadata=PngImagePlugin.PngInfo()
        metadata.add_text("Author","ZHAOYUN / \u8d75\u4e91")
        metadata.add_text("Description","SGODOT-322 white blockout, SGODOT-317 R3 reference; actual Godot Mobile/Vulkan capture")
        image.convert("RGB").save(path,pnginfo=metadata)
        assert path.stat().st_size<4_000_000
        files.append(path)
    clean=Image.open(QA/"captures/default_clean_720.png").convert("RGB")
    assert clean.size==(720,1600) and np.asarray(clean).std()>12
    save(clean,"default_clean")
    marked=clean.copy();draw=ImageDraw.Draw(marked)
    for y0,y1 in [(0,200),(1420,1600)]:draw.rectangle((0,y0,719,y1),fill="#304955")
    draw.line((0,200,720,200),fill="#60B8BD",width=3);draw.line((0,1420,720,1420),fill="#60B8BD",width=3)
    draw.text((24,24),"CLASSROOM | WHITE V0",font=font(30),fill="white")
    draw.text((24,78),"43 deg / 45 deg / 6.72 m",font=font(26),fill="#D2E0E5")
    draw.text((24,133),"HUD SAFE: 100 px at 360 width",font=font(24),fill="#D2E0E5")
    draw.text((24,1448),"BACKPACK SAFE: 90 px at 360 width",font=font(24),fill="#D2E0E5")
    draw.text((24,1515),"SGODOT-322 | ZHAOYUN / \u8d75\u4e91",font=font(27),fill="white")
    save(marked,"default_43")
    top=Image.open(QA/"captures/topdown.png").convert("RGB")
    image=Image.new("RGB",(1200,1420),"#F4F6F6");image.paste(top,(0,0));draw=ImageDraw.Draw(image)
    def project(x,z):return (600+x*150,600+z*150)
    def arrow(a,b,label,color="#207A7E",offset=(0,-28)):
        draw.line([a,b],fill=color,width=3)
        dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);ux,uy=dx/length,dy/length
        for p,sign in [(a,1),(b,-1)]:
            draw.polygon([p,(p[0]+ux*12*sign-uy*5,p[1]+uy*12*sign+ux*5),
                          (p[0]+ux*12*sign+uy*5,p[1]+uy*12*sign-ux*5)],fill=color)
        mid=((a[0]+b[0])/2+offset[0],(a[1]+b[1])/2+offset[1])
        draw.text(mid,label,font=font(22),fill=color,anchor="mm",stroke_width=2,stroke_fill="#F4F6F6")
    arrow((90,70),(1110,70),"6.80 m",offset=(0,-23))
    arrow((55,120),(55,1080),"6.40 m",offset=(0,0))
    arrow(project(-.04,.30),project(1.09,.30),"1.13 m")
    arrow(project(-2.67,1.55),project(-1.06,1.55),"1.61 m")
    arrow(project(2.11,.30),project(3.34,.30),"1.23 m")
    arrow(project(-1.80,-.73),project(-1.06,-.73),"0.74 m",offset=(0,-30))
    arrow(project(.5,-2.0185),project(.5,-1.24),"0.779 m",offset=(68,0))
    arrow(project(2.50,2.32),project(2.50,3.14),"0.82 m",offset=(-55,0))
    for row in plan["anchors"]:
        if row["name"].startswith("seat_"):
            x,y=project(row["position"][0],row["position"][2])
            draw.ellipse((x-22,y-22,x+22,y+22),fill="#3E6879",outline="#FFFFFF",width=2)
            draw.text((x,y-1),"S"+row["name"].rsplit("_",1)[1],font=font(20),fill="white",anchor="mm")
    for name,label,color in [("spawn","SPAWN","#3C8471"),("exit","EXIT","#3C8471")]:
        anchor=next(a for a in plan["anchors"] if a["name"]==name);x,y=project(anchor["position"][0],anchor["position"][2])
        draw.ellipse((x-9,y-9,x+9,y+9),fill=color)
        draw.text((x,y+22),label,font=font(22),fill=color,anchor="mm",stroke_width=2,stroke_fill="#F4F6F6")
    draw.text((600,1140),"SGODOT-322 | White blockout / measured top view",font=font(29),fill="#273C43",anchor="mm")
    draw.text((40,1200),"6 seats: S1-S6 | seat top 0.715 m above floor (Y = 0.795 m)",font=font(24),fill="#273C43")
    draw.text((40,1244),"Native capsule: radius 0.25 m / height 1.745 m | main route: radius 0.35 m",font=font(23),fill="#273C43")
    draw.text((40,1288),"16 clear standing positions in validation | desk top 1.02 x 0.58 m",font=font(23),fill="#273C43")
    draw.text((40,1344),"ZHAOYUN / \u8d75\u4e91 | 2026-11-03 | Final prop files remain owned by Huangzhong",font=font(22),fill="#273C43")
    save(image,"topdown_ruler")
    seated=Image.open(QA/"captures/seated_overview.png").convert("RGB")
    sheet=Image.new("RGB",(1200,1070),"#F4F6F6");sheet.paste(seated,(0,0))
    ImageDraw.Draw(sheet).text((22,1018),"6 native sit_idle poses | 0.715 m seats | SGODOT-322 | ZHAOYUN / \u8d75\u4e91",font=font(25),fill="#273C43")
    save(sheet,"six_seats")
    prior=ROOT/"assets/rooms/_shared/shell_hall"
    provenance={"shared_shell_unchanged":True,"shared_shell_files":[{"path":str(p.relative_to(ROOT)),"sha256":digest(p)} for p in sorted(prior.glob("hall_*.glb"))],
        "props_pending_source":"350bd1f1 / PR #689 / assets/rooms/poi_classroom/props/","final_props_not_copied":not (KIT/"props").exists()}
    evidence={"phase":"white blockout, detailed art awaits approval","glbs":glbs,"plan":planar,"navigation":navigation,"godot":render,"provenance":provenance,
        "source_blend_sha256":digest(HERE/"classroom_blockout.blend"),"layout_sha256":digest(KIT/"layout.json"),
        "stage":json.loads((QA/"stage.json").read_text()),"scope":"P0 art fixture, existing animation and physical capsule sweeps; no final atlas or multiplayer/POI service integration"}
    (DEST/"validation-white-v0.json").write_text(json.dumps(evidence,indent=2)+"\n")
    (DEST/"media-manifest-white-v0.json").write_text(json.dumps([{"name":p.name,"path":str(p.relative_to(ROOT)),"sha256":digest(p),"bytes":p.stat().st_size,
        "mime":"image/png","size":list(Image.open(p).size)} for p in files],indent=2)+"\n")
    print("CLASSROOM_PACKAGE",len(files),"images",render["triangles"],"triangles",render["surfaces"],"surfaces; min passage",min(planar["main_corridors_m"].values()))
if __name__=="__main__":main()
