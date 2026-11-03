"""N3 colour-only revision: verify preserved regions and package three game views."""
from pathlib import Path
import colorsys
import hashlib
import io
import json
import subprocess
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, PngImagePlugin

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
KIT=ROOT/"assets/rooms/poi_culture_hall";QA=ROOT/"output/culture-hall-323"
DEST=ROOT/"docs/design/poi-culture-hall-323-2026-11-03"
BASE="a5ffdae1";PREFIX="SGODOT-323_POI_CULTURE_HALL_v1.1_"
sys.path.insert(0,str(ROOT/"tools/art"))
from verify_chef_sign import load_glb,accessor


def old(path):return subprocess.check_output(["git","show",BASE+":"+str(path)],cwd=ROOT)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def font(size):return ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",size)


def main():
    layout=json.loads((KIT/"layout.json").read_text());stats=json.loads((KIT/"asset_stats.json").read_text())
    before=json.loads(old("assets/rooms/poi_culture_hall/layout.json"))
    render=json.loads((QA/"captures-v11/validation.json").read_text())
    assets=json.loads((QA/"detail-assets.json").read_text())
    independent=json.loads((QA/"reuse-assets.json").read_text())
    source=json.loads((QA/"assembly-source.json").read_text())
    assert all(r["passed"] for r in [render,assets,independent,source])
    assert render["input_sha256"]==dict(layout=digest(KIT/"layout.json"),atlas=digest(KIT/"room_albedo_ao.png"),mosaic=digest(KIT/"props/floor_mosaic.glb"))
    for log in ["import-v11.log","render-v11.log","source-v11.log"]:
        text=(QA/log).read_text();assert "ERROR:" not in text and "Traceback" not in text,log
    previous=json.loads((DEST/"validation-v1.json").read_text())
    assert render["native_camera"]==previous["godot"]["native_camera"]
    assert render["triangles"]==stats["scene_triangles"]==23884 and render["surfaces"]==stats["static_draw_surfaces"]==28
    invariants=["anchors","spawn","exit","camera","local_lights","review_lighting","rear_clear_band"]
    assert all(layout[k]==before[k] for k in invariants),"Only material metadata may change in the layout"
    old_rows={r["name"]:r for r in before["placements"]}
    for row in layout["placements"]:
        compared=dict(row)
        if row["name"]=="floor_mosaic":compared["role"]=old_rows["floor_mosaic"]["role"]
        assert compared==old_rows[row["name"]],row["name"]
    assert len(layout["placements"])==len(old_rows)
    art_path=Path("scenes/poi_culture_hall/poi_culture_hall_art.gd")
    assert (ROOT/art_path).read_bytes()==old(art_path)

    # Raw atlas comparison guarantees that recolouring did not touch floor,
    # shared plant cards, furniture or alpha, including unused padding pixels.
    baseline=np.asarray(Image.open(io.BytesIO(old("assets/rooms/poi_culture_hall/room_albedo_ao.png"))).convert("RGBA"))
    current=np.asarray(Image.open(KIT/"room_albedo_ao.png").convert("RGBA"))
    skin=json.loads((KIT/"atlas_skin.json").read_text());allowed=np.zeros((2048,2048),bool)
    slots={}
    for name in ["plaster","plaster_solid","panel","wainscot_solid"]:
        slot=skin["slots"][name];x,y,w,h=slot["rect_px_top_left"];allowed[y:y+h,x:x+w]=True
        slots[name]=dict(rect_px_top_left=[x,y,w,h],hex_srgb=slot["hex_srgb"])
    changed=np.any(baseline!=current,axis=2)
    assert changed.any() and not np.any(changed&~allowed) and np.array_equal(baseline[:,:,3],current[:,:,3])

    retained=[]
    for spec in layout["assets"]:
        path=KIT/spec["file"];rel=path.relative_to(ROOT)
        if spec["name"]!="props/floor_mosaic":
            assert path.read_bytes()==old(rel),rel
            retained.append(str(rel))
        assert Path(str(path)+".import").read_bytes()==old(str(rel)+".import"),str(rel)+".import"
    raw_before=QA/"floor_mosaic_before_v11.glb"
    raw_before.write_bytes(old("assets/rooms/poi_culture_hall/props/floor_mosaic.glb"))
    a,ab=load_glb(raw_before);b,bb=load_glb(KIT/"props/floor_mosaic.glb")
    assert a["nodes"]==b["nodes"],"Mosaic node hierarchy and transforms unchanged"
    before_p=[p for m in a["meshes"] for p in m["primitives"]];after_p=[p for m in b["meshes"] for p in m["primitives"]]
    assert len(before_p)==len(after_p)==1
    geometry_checks=[]
    for old_p,new_p in zip(before_p,after_p):
        assert old_p["attributes"].keys()==new_p["attributes"].keys()
        # Exporters may merge/split vertices at changed colour seams. Compare
        # oriented triangle attributes, allowing only index renumbering.
        keys=sorted(k for k in old_p["attributes"] if k!="COLOR_0")
        def triangles(doc,blob,primitive):
            values=np.concatenate([np.asarray(accessor(doc,blob,primitive["attributes"][k])) for k in keys],axis=1)
            indices=np.asarray(accessor(doc,blob,primitive["indices"])).reshape(-1,3)
            result=[]
            for triangle in np.rint(values[indices]*1e6).astype(np.int64):
                corners=[tuple(v) for v in triangle]
                result.append(min(tuple(corners[i:]+corners[:i]) for i in range(3)))
            return sorted(result)
        assert triangles(a,ab,old_p)==triangles(b,bb,new_p),"Mosaic oriented triangle geometry/attributes unchanged"
        geometry_checks=keys+["oriented triangle topology (index numbering may differ)"]
        assert not np.array_equal(accessor(a,ab,old_p["attributes"]["COLOR_0"]),accessor(b,bb,new_p["attributes"]["COLOR_0"]))

    old_overview=Image.open(DEST/"SGODOT-323_POI_CULTURE_HALL_v1_overview.png").convert("RGB")
    new_overview=Image.open(QA/"captures-v11/overview.png").convert("RGB")
    samples=[]
    for probe in render["wall_probes"]:
        x,y=map(round,probe["pixel"]);row=dict(probe,patch_size_px=9)
        for key,im in [("before",old_overview),("after",new_overview)]:
            rgb=np.median(np.asarray(im)[y-4:y+5,x-4:x+5].reshape(-1,3),axis=0).astype(int)
            h,s,v=colorsys.rgb_to_hsv(*(rgb/255))
            row[key]=dict(hex="#"+"".join(f"{c:02X}" for c in rgb),hue_deg=h*360,saturation=s,value=v)
        if probe["name"].endswith("wall"):
            assert row["after"]["saturation"]>row["before"]["saturation"]+.05
            assert 20<row["after"]["hue_deg"]<40
        samples.append(row)

    files=[]
    def raw(name):
        im=Image.open(QA/"captures-v11"/(name+".png")).convert("RGB");assert np.asarray(im).std()>12;return im
    def save(im,name):
        path=DEST/(PREFIX+name+".png");meta=PngImagePlugin.PngInfo()
        meta.add_text("Author","ZHAOYUN / 赵云")
        meta.add_text("Description","SGODOT-323 v1.1; warmer apricot walls and supplier concentric cream/terracotta mosaic; original floor and lighting")
        im.save(path,pnginfo=meta);assert path.stat().st_size<4_000_000;files.append(path)
    clean=raw("default_clean_720");assert clean.size==(720,1600);save(clean,"default_clean")
    seats=raw("seated_overview");out=Image.new("RGB",(seats.width,seats.height+70),"#F3F6F6");out.paste(seats,(0,0))
    ImageDraw.Draw(out).text((20,seats.height+22),"4 native sit_idle poses | .715 m seats | warm wall / mosaic v1.1 | ZHAOYUN / 赵云",font=font(22),fill="#29454A")
    save(out,"four_seats")
    reference=Image.open(HERE/"reference/SGODOT-318_Culture_Hall_Main_2026-10-31.png").convert("RGB")
    comparison=Image.new("RGB",(2400,1250),"#F3F6F6")
    for im,x in [(reference,0),(raw("reference_camera"),1200)]:
        im.thumbnail((1180,1100),Image.Resampling.LANCZOS);comparison.paste(im,(x+(1200-im.width)//2,60+(1100-im.height)//2))
    d=ImageDraw.Draw(comparison);d.text((30,15),"Stark 318 R3 main",font=font(28),fill="#29454A")
    d.text((1230,15),"N3 v1.1 | Godot Mobile Vulkan",font=font(28),fill="#29454A")
    d.text((30,1170),"对照机位：按主图地板边估算 35.26° / 45°；实际开场仍为 43° / 6.72 m。布局遵循 323 已批 2 m 留空提案。",font=font(26),fill="#29454A")
    d.text((30,1210),"暖杏墙与护墙板 + 暖奶油/浅赤陶同心圆拼花；地砖和光照保留。原始游戏渲染，无后期调色。ZHAOYUN / 赵云",font=font(25),fill="#29454A")
    save(comparison,"stark_comparison")

    report=dict(passed=True,baseline=BASE,colour_slots=slots,changed_atlas_pixels=int(changed.sum()),outside_slots_identical=True,alpha_identical=True,
                retained_glbs=retained,mosaic_unchanged_arrays=geometry_checks,layout_invariants=invariants,
                placements_unchanged_except="floor_mosaic.role descriptive text, now identifies the warm colour rings",
                samples=samples,sample_note="Same projected points and median 9x9 patches in unedited 1200x1000 overview; different from director's unspecified sample points",
                assets=assets,independent=independent,editable_source=source,godot=render,stats=stats,
                navigation=dict(source="validation-v1.json",passed=previous["navigation"]["passed"],basis="Same mesh geometry, placement, collision declarations and assembly script as accepted a5ffdae1"),
                source_blend_sha256=digest(HERE/"culture_hall_v1.blend"),scope="Colour-only art review; existing native camera, lighting, geometry and navigation retained")
    (DEST/"validation-v1.1.json").write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n")
    (DEST/"media-manifest-v1.1.json").write_text(json.dumps([dict(name=p.name,path=str(p.relative_to(ROOT)),sha256=digest(p),bytes=p.stat().st_size,mime="image/png",size=list(Image.open(p).size)) for p in files],indent=2)+"\n")
    print("CULTURE_V11_PACKAGE",len(files),"images",report["changed_atlas_pixels"],"wall/panel pixels")
    for s in samples:print(s["name"],s["before"]["hex"],"->",s["after"]["hex"])


if __name__=="__main__":main()
