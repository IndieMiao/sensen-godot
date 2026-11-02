"""Package native captures and quantitative evidence for the quarry v0 review."""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np
from PIL import Image,ImageDraw,ImageFont

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[4];QA=ROOT/"output/quarry-355"
DEST=ROOT/"docs/design/quarry-355-2026-11-02"
PREFIX="SGODOT-355_mine_quarry_v0_"
parser=argparse.ArgumentParser();parser.add_argument("--runtime",required=True);args=parser.parse_args()
runtime=Path(args.runtime);kit=runtime/"assets/mine/types/quarry"
raw=QA/"captures";DEST.mkdir(parents=True,exist_ok=True)
glb=json.loads((QA/"glb-validation.json").read_text());godot=json.loads((raw/"validation.json").read_text())
assert glb["passed"] and godot["passed"]
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
assert glb["runtime_glb_sha256"]==digest(kit/"backdrop.glb")
def lightness(rgb):
    v=np.asarray(rgb)/255
    v=np.where(v<=.04045,v/12.92,((v+.055)/1.055)**2.4)
    y=float(v@np.array([.2126,.7152,.0722]))
    return 116*y**(1/3)-16 if y>.008856 else y*903.3
pixels=[]
for index,band in enumerate(godot["bands"],1):
    on=np.asarray(Image.open(raw/f"band_{index}.png").convert("RGB"),dtype=float)
    off=np.asarray(Image.open(raw/f"band_{index}_backdrop_off.png").convert("RGB"),dtype=float)
    subject=np.max(np.abs(off-off[0,0]),axis=2)>2
    delta=np.max(np.abs(on-off),axis=2)
    protected_error=float(delta[subject].max())
    assert protected_error==0
    row={"band":index,"protected_subject_max_error_rgb255":protected_error,
        "protected_subject_pixels":int(subject.sum()),"changed_background_pixels":int((delta>2).sum())}
    for role in ["coal","floor"]:
        x,y=map(round,band[role+"_pixel"])
        rgb=np.median(on[y-1:y+2,x-1:x+2].reshape(-1,3),axis=0)
        row[role]={"pixel":[x,y],"rgb":rgb.tolist(),"L_star":lightness(rgb)}
    row["floor_minus_coal_L_star"]=row["floor"]["L_star"]-row["coal"]["L_star"]
    assert row["floor_minus_coal_L_star"]>=10
    pixels.append(row)
font=lambda size:ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",size)
files=[]
def save_jpg(image,name,description):
    path=DEST/(PREFIX+name+".jpg")
    exif=Image.Exif();exif[315]="ZHAOYUN";exif[270]=description
    image.convert("RGB").save(path,quality=93,subsampling=0,optimize=True,exif=exif)
    assert path.stat().st_size<3_000_000
    files.append(path)
    return path
names=["band_1","band_2","band_3","band_4","guard_30"]
labels=["QUARRY | 1-4","QUARRY | 5-10","QUARRY | 11-20","QUARRY | 21-30","GUARD ARENA | 30"]
sheet=Image.new("RGB",(3696,1800),"#f3f4f2");draw=ImageDraw.Draw(sheet)
draw.text((20,12),"SGODOT-355 | QUARRY V0 | Native P0 camera: 43 deg / 14.5 deg / 6.72 m",font=font(32),fill="#242125")
draw.text((20,58),"Back row: Slime / Rock Beetle / Shroomling / Cave Bat. Front rocks: Iron / Quartz / Coal / Copper.",font=font(24),fill="#46423f")
for i,(name,label) in enumerate(zip(names,labels)):
    image=Image.open(raw/(name+".png")).convert("RGB")
    assert image.size==(720,1600) and np.asarray(image).std()>20
    save_jpg(image,name,"SGODOT-355 quarry v0; 720x1600 native Mobile/Vulkan art fixture; 43deg pitch, 14.5deg yaw, 6.72m; author ZHAOYUN")
    x=16+i*736
    draw.text((x,100),label,font=font(28),fill="#242125")
    sheet.paste(image,(x,146))
draw.text((20,1754),"ZHAOYUN / \u8d75\u4e91 | 2026-11-02 | 2,968 triangles / 1 surface / vertex grayscale / UV2.y = 0 | v0 for art review",font=font(26),fill="#242125")
save_jpg(sheet,"bands","Signed five-view quarry v0 review: four bands and guard arena, ZHAOYUN")
overview=Image.open(raw/"overview.png").convert("RGB")
page=Image.new("RGB",(1200,960),"#f3f4f2");page.paste(overview,(0,0))
ImageDraw.Draw(page).text((18,916),"Quarry v0 overview (22 m) | ZHAOYUN / \u8d75\u4e91 | 2,968 triangles",font=font(25),fill="#242125")
save_jpg(page,"overview","Non-default 22m overview of complete quarry relief and guard arena; ZHAOYUN")
depth=json.loads((QA/"depth-full.json").read_text())
assert len(depth["cases"])==10 and depth["zoom_step"]==.01 and depth["across_step"]==.05
assert all(case["worst"]["far_margin"]>=.05 and case["near_margin"]>0 for case in depth["cases"])
evidence={"glb":glb,"godot":godot,"pixels":pixels,"depth_full":depth,"stage":json.loads((QA/"stage.json").read_text()),
    "source_blend_sha256":digest(HERE/"quarry.blend"),"source_parent":json.loads((QA/"build.json").read_text())["source_sha256"],
    "runtime_files":[{"path":str(p.relative_to(runtime)),"sha256":digest(p),"bytes":p.stat().st_size} for p in sorted(kit.iterdir()) if p.is_file()],
    "scope":"Desktop Mobile/Vulkan art fixture with temporary palette and mask shader overlays only. No gameplay integration or physical-device performance claim."}
(DEST/"validation-v0.json").write_text(json.dumps(evidence,indent=2)+"\n")
(DEST/"media-manifest-v0.json").write_text(json.dumps([{"name":p.name,"path":str(p.relative_to(ROOT)),"sha256":digest(p),
    "bytes":p.stat().st_size,"mime":"image/jpeg","size":list(Image.open(p).size)} for p in files],indent=2)+"\n")
print("QUARRY_PACKAGE",len(files),"images; min floor-minus-coal L*",min(p["floor_minus_coal_L_star"] for p in pixels),
    "far margin",min(c["worst"]["far_margin"] for c in depth["cases"]))
