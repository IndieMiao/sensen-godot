"""Signed N3 v1 game renders and validation evidence; no synthetic room images."""
from pathlib import Path
import hashlib
import json
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, PngImagePlugin

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
QA = ROOT / "output/culture-hall-323"
KIT = ROOT / "assets/rooms/poi_culture_hall"
DEST = ROOT / "docs/design/poi-culture-hall-323-2026-11-03"
PREFIX = "SGODOT-323_POI_CULTURE_HALL_v1_"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def font(size):
    return ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", size)


def main():
    layout = json.loads((KIT / "layout.json").read_text())
    stats = json.loads((KIT / "asset_stats.json").read_text())
    reports = {key: json.loads((QA / name).read_text()) for key, name in {
        "plan": "plan-validation.json", "navigation": "navigation.json", "independent_assets": "reuse-assets.json",
        "display_assets": "detail-assets.json", "editable_source": "assembly-source.json",
        "godot": "captures-v1/validation.json"}.items()}
    assert all(r["passed"] for r in reports.values())
    for log in ["import-detail.log", "reimport-detail.log", "configure-detail.log", "navigation-detail.log", "render-detail.log", "source-detail.log"]:
        text = (QA / log).read_text()
        assert "ERROR:" not in text and "Traceback" not in text, log
    baseline = json.loads((DEST / "validation-white-v0.json").read_text())
    assert reports["godot"]["native_camera"] == baseline["godot"]["native_camera"]
    assert (reports["godot"]["triangles"], reports["godot"]["surfaces"]) == (stats["scene_triangles"], stats["static_draw_surfaces"])
    files = []

    def raw(name):
        im = Image.open(QA / "captures-v1" / (name + ".png")).convert("RGB")
        assert np.asarray(im).std() > 12
        return im

    def save(im, name):
        path = DEST / (PREFIX + name + ".png")
        meta = PngImagePlugin.PngInfo()
        meta.add_text("Author", "ZHAOYUN / 赵云")
        meta.add_text("Description", "SGODOT-323 assembled v1; Godot Mobile Vulkan; Huangzhong approved props 6d21e183, case enlargement pending")
        im.save(path, pnginfo=meta)
        assert path.stat().st_size < 4_000_000
        files.append(path)

    def caption(im, text):
        out = Image.new("RGB", (im.width, im.height + 70), "#F3F6F6")
        out.paste(im, (0, 0))
        ImageDraw.Draw(out).text((20, im.height + 21), text, font=font(22), fill="#29454A")
        return out

    clean = raw("default_clean_720")
    assert clean.size == (720, 1600)
    save(clean, "default_clean")
    safe = clean.copy()
    d = ImageDraw.Draw(safe)
    for y0, y1 in [(0, 200), (1420, 1600)]:
        d.rectangle((0, y0, 719, y1), fill="#344E53")
    d.text((24, 25), "CULTURE HALL | ASSEMBLED V1", font=font(29), fill="white")
    d.text((24, 81), "43 deg / 45 deg / 6.72 m", font=font(26), fill="#D4E8E5")
    d.text((24, 137), "HUD SAFE: 100 px at 360 width", font=font(24), fill="#D4E8E5")
    for y in [200, 1420]:
        d.line((0, y, 720, y), fill="#8CCCB9", width=3)
    d.text((24, 1450), "BAG SAFE: 90 px at 360 width", font=font(25), fill="#D4E8E5")
    d.text((24, 1520), "SGODOT-323 | ZHAOYUN / 赵云", font=font(26), fill="white")
    save(safe, "default_43_safe")
    viewing = raw("viewing_area_720")
    d = ImageDraw.Draw(viewing)
    d.rectangle((0, 1420, 719, 1599), fill="#344E53")
    d.text((22, 1445), "VIEWING AREA | NOT THE ENTRY SHOT", font=font(24), fill="white")
    d.text((22, 1493), "Player [.65, .08, -1.70] | 43 deg / 6.72 m", font=font(23), fill="#D4E8E5")
    d.text((22, 1540), "ZHAOYUN / 赵云", font=font(25), fill="white")
    save(viewing, "viewing_area")
    save(caption(raw("seated_overview"), "3 bench seats + 1 stool | native sit_idle / .715 m seat | ZHAOYUN / 赵云"), "four_seats")
    save(caption(raw("overview"), "43 deg panorama | 23,140 triangles / 28 surfaces | ZHAOYUN / 赵云"), "overview")

    top = raw("topdown").convert("RGBA")
    overlay = Image.new("RGBA", top.size)
    d = ImageDraw.Draw(overlay)
    def xy(x, z):
        return (600+x*150, 600+z*150)
    x0, z0, x1, z1 = layout["rear_clear_band"]
    d.rectangle((*xy(x0,z0), *xy(x1,z1)), fill=(91,166,143,55), outline="#377E69", width=3)
    d.text(xy(.05,-2.05), "2.00 m CLEAR VIEWING STRIP", font=font(25), fill="#245C4F", anchor="mm")
    top = Image.alpha_composite(top, overlay).convert("RGB")
    d = ImageDraw.Draw(top)
    def arrow(a, b, label):
        a,b = xy(*a),xy(*b)
        d.line([a,b], fill="#2C7382", width=3)
        dx,dy = b[0]-a[0],b[1]-a[1]
        length = math.hypot(dx,dy)
        ux,uy = dx/length,dy/length
        d.polygon([b,(b[0]-ux*12-uy*5,b[1]-uy*12+ux*5),(b[0]-ux*12+uy*5,b[1]-uy*12-ux*5)],fill="#2C7382")
        if label:
            d.text(((a[0]+b[0])/2,(a[1]+b[1])/2-23),label,font=font(22),fill="#2C7382",anchor="mm",stroke_width=2,stroke_fill="white")
    for target in layout["review_targets"]:
        if target.get("direct"):
            arrow((layout["spawn"][0],layout["spawn"][2]),(target["position"][0],target["position"][2]),"")
    arrow((-2.35,.65),(-1.567,.65),".783 m")
    arrow((2.20,.916),(2.20,1.620),".704 m")
    for i,seat in enumerate([a for a in layout["anchors"] if a["name"].startswith("seat_")],1):
        x,y=xy(seat["position"][0],seat["position"][2])
        d.ellipse((x-21,y-21,x+21,y+21),fill="#3D6879",outline="white",width=2)
        d.text((x,y),"S%d"%i,font=font(21),anchor="mm",fill="white")
    d.line([(90,65),(1110,65)],fill="#377E69",width=3)
    d.text((600,40),"6.80 m",font=font(25),anchor="mm",fill="#29454A")
    d.line([(60,120),(60,1080)],fill="#377E69",width=3)
    d.text((65,590),"6.40 m",font=font(25),fill="#29454A")
    save(caption(top,"4 seats / 16 positions | 3 direct routes | actual rear net 2.006 m | ZHAOYUN"),"topdown_ruler")

    reference = Image.open(HERE / "reference/SGODOT-318_Culture_Hall_Main_2026-10-31.png").convert("RGB")
    rendering = raw("reference_camera")
    comparison = Image.new("RGB", (2400,1250), "#F3F6F6")
    for im,x in [(reference,0),(rendering,1200)]:
        im.thumbnail((1180,1100),Image.Resampling.LANCZOS)
        comparison.paste(im,(x+(1200-im.width)//2,60+(1100-im.height)//2))
    d=ImageDraw.Draw(comparison)
    d.text((30,15),"Stark 318 R3 main",font=font(28),fill="#29454A")
    d.text((1230,15),"N3 v1 | Godot Mobile Vulkan",font=font(28),fill="#29454A")
    d.text((30,1170),"对照机位：按主图地板边估算 35.26° / 45°；实际开场仍为 43° / 6.72 m。布局遵循 323 已批 2 m 留空提案。",font=font(26),fill="#29454A")
    d.text((30,1210),"展柜内展品为黄忠 v1；放大版待替换。画面无调色，整间保留。ZHAOYUN / 赵云",font=font(25),fill="#29454A")
    save(comparison,"stark_comparison")

    reports.update(stats=stats, layout_sha256=digest(KIT/"layout.json"), atlas_sha256=digest(KIT/"room_albedo_ao.png"),
                   source_blend_sha256=digest(HERE/"culture_hall_v1.blend"),
                   stage=json.loads((QA/"stage.json").read_text()),
                   opening_approved="95aed0c2 / 1eb4f28b; exact same native player-follow camera as approved white stage",
                   pending="Supplier case_exhibits_1/_2 enlargement; current approved v1 kept byte-identical",
                   scope="Game-rendered art review; isolated copied P0 runtime, near=.1/far=40 hall contract; no public-client changes or device/service acceptance")
    (DEST/"validation-v1.json").write_text(json.dumps(reports,indent=2,ensure_ascii=False)+"\n")
    (DEST/"media-manifest-v1.json").write_text(json.dumps([dict(name=p.name,path=str(p.relative_to(ROOT)),sha256=digest(p),bytes=p.stat().st_size,mime="image/png",size=list(Image.open(p).size)) for p in files],indent=2)+"\n")
    print("CULTURE_V1_PACKAGE",len(files),"images",stats["scene_triangles"],"triangles",stats["static_draw_surfaces"],"surfaces")


if __name__ == "__main__":
    main()
