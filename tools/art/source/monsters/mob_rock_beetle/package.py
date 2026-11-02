"""Package the graybox review and read back the actual native-rendered pixels."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFont, PngImagePlugin

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[4]
QA=ROOT/"output/rock-beetle-355"
DEST=ROOT/"docs/design/rock-beetle-355-2026-11-02"
PREFIX="SGODOT-355_mob_rock_beetle_graybox_"
parser=argparse.ArgumentParser();parser.add_argument("--runtime",required=True);args=parser.parse_args()
runtime=Path(args.runtime).resolve()
kit=runtime/"assets/monsters/mob_rock_beetle"
DEST.mkdir(parents=True,exist_ok=True)
raw=QA/"captures"
report=json.loads((raw/"validation.json").read_text())
glb=json.loads((QA/"glb-validation.json").read_text())
assert report["passed"] and glb["passed"]
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
assert digest(kit/"mob_rock_beetle.glb")==glb["runtime_glb_sha256"]
a=np.asarray(Image.open(raw/"tint_base.png").convert("RGB"),dtype=float)
b=np.asarray(Image.open(raw/"tint_changed.png").convert("RGB"),dtype=float)
delta=np.max(np.abs(a-b),axis=2)
x,y=map(round,report["tint_eye_pixel"])
eye_delta=float(np.max(delta[y-2:y+3,x-2:x+3]))
changed=int((delta>10).sum())
assert changed>1000 and eye_delta<=2
stunned=[np.asarray(Image.open(raw/("stunned_%d.png"%i)).convert("RGB"),dtype=float) for i in range(4)]
stun_changes=[int((np.max(np.abs(stunned[0]-im),axis=2)>8).sum()) for im in stunned[1:]]
assert min(stun_changes)>100
fontpath="/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
font=lambda n:ImageFont.truetype(fontpath,n)
def sheet(title,frames,columns):
    cell=560;rows=(len(frames)+columns-1)//columns
    out=Image.new("RGB",(cell*columns+32,rows*(cell+40)+110),"#F5F5F2")
    draw=ImageDraw.Draw(out)
    draw.text((24,12),title,fill="#28352F",font=font(26))
    for i,(file,label) in enumerate(frames):
        image=Image.open(raw/(file+".png")).convert("RGB")
        assert np.asarray(image).std()>12
        image.thumbnail((cell-16,cell),Image.Resampling.LANCZOS)
        x0=16+(i%columns)*cell;y0=58+(i//columns)*(cell+40)
        out.paste(image,(x0+(cell-16-image.width)//2,y0))
        draw.text((x0,y0+cell),label,fill="#28352F",font=font(20))
    draw.text((24,out.height-34),"SGODOT-355 | GRAYBOX G0 | ZHAOYUN / \u8d75\u4e91 | 2026-11-02",fill="#28352F",font=font(20))
    return out
views=sheet("Rock Beetle | %s triangles / 11 bones / rigid skin" % format(glb["triangles"], ","),
    [("front","Front +Z"),("side","Right side"),("top","Top")],3)
anims=json.loads((kit/"mob_rock_beetle.json").read_text())["anims"]
actions=[("action_"+name,name+" / "+str(data["length"])+" s"+(" / loop" if data["loop"] else "")) for name,data in anims.items()]
actions += [("stunned_%d"%i,"stunned / %.2f s"%(i*.25)) for i in range(4)]
motion=sheet("Rock Beetle | Eight final action names + stunned cycle samples",actions,4)
files=[]
for name,im in [("three_views",views),("actions",motion)]:
    path=DEST/(PREFIX+name+".png");im.save(path);files.append(path)
for name in ["mine_360","mine_720"]:
    im=Image.open(raw/(name+".png")).convert("RGB")
    meta=PngImagePlugin.PngInfo()
    meta.add_text("Author","ZHAOYUN / \u8d75\u4e91")
    meta.add_text("Description","SGODOT-355 graybox G0; native farm-dev MineArt floor 3, slime and Avatar; 43 degrees, width 6.72 m. Static art fixture, no combat integration.")
    path=DEST/(PREFIX+name+".png");im.save(path,pnginfo=meta);files.append(path)
runtime_files=[]
for p in sorted(kit.iterdir()):
    if p.is_file(): runtime_files.append({"path":str(p.relative_to(runtime)),"sha256":digest(p),"bytes":p.stat().st_size})
evidence={"glb":glb,"godot":report,"tint_pixels":{"body_changed_pixels":changed,"protected_eye_max_error_rgb255":eye_delta},
    "stunned_changed_pixels":stun_changes,"runtime_files":runtime_files,
    "source_blend_sha256":digest(HERE/"mob_rock_beetle.blend"),
    "runtime_base":json.loads((QA/"stage-snapshot.json").read_text())["runtime_game_base"],
    "shared_import_source":"art/monsters-355 b3a4f713 assets/monsters/material_import.gd",
    "scope":"Graybox contract and desktop Mobile/Vulkan art verification. No production account, AI/combat wiring, Android or physical-device performance."}
(DEST/"validation-graybox.json").write_text(json.dumps(evidence,indent=2)+"\n")
(DEST/"media-manifest-graybox.json").write_text(json.dumps([{"name":p.name,"path":str(p.relative_to(ROOT)),"sha256":digest(p),
    "bytes":p.stat().st_size,"size":list(Image.open(p).size)} for p in files],indent=2)+"\n")
print("BEETLE_GRAYBOX_PACKAGE",len(files),"images; tint body pixels",changed,"eye error",eye_delta,"stunned",stun_changes)
