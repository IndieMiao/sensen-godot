"""Publish verified N1 art-review media and reproducible evidence, without changing image framing."""
from pathlib import Path
import colorsys
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont, PngImagePlugin

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / "assets/rooms/poi_hotel_lobby"
HALL = ROOT / "assets/rooms/_shared/shell_hall"
QA = ROOT / "output/hotel-lobby-319"
DEST = ROOT / "docs/design/poi-hotel-lobby-319-2026-10-31"
PREFIX = "SGODOT-319_N1_v1_"
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"


def font(size): return ImageFont.truetype(FONT, size)
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def dump(path, data): path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def sheet(width, height, title):
    out = Image.new("RGB", (width, height), "#F5F5F2")
    draw = ImageDraw.Draw(out)
    draw.text((24, 12), title, fill="#293330", font=font(25))
    draw.text((24, height - 36), "SGODOT-319 | N1 HOTEL LOBBY | ZHAOYUN / \u8d75\u4e91 | 2026-10-31", fill="#293330", font=font(19))
    return out


def fit(image, box):
    image = image.copy(); image.thumbnail(box, Image.Resampling.LANCZOS)
    return image


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    raw = QA / "captures"
    geometry = json.loads((QA / "geometry-validation.json").read_text())
    runtime = json.loads((raw / "godot-validation.json").read_text())
    early = json.loads((QA / "plan/godot-navigation.json").read_text())
    plan = json.loads((QA / "plan/plan-validation.json").read_text())
    native_path = QA / "native-camera.json"
    if not native_path.exists(): native_path = DEST / "native-camera-n1-v1.json"
    native = json.loads(native_path.read_text())
    assert geometry["passed"] and runtime["passed"] and early["passed"] and plan["passed"]
    assert native["layout_sha256"] == digest(KIT / "layout.json")
    assert "SCRIPT ERROR" not in (QA / "render.log").read_text()
    files = []
    for source, title in [("full", "Hotel Lobby | 43-degree complete panorama"), ("top", "Hotel Lobby | Orthographic plan"),
        ("hearth", "Hotel Lobby | Fireplace and mantel"), ("keys", "Hotel Lobby | Key rack, three clocks and blank name plaque"),
        ("sofa", "Hotel Lobby | Six-seat ring sofa and central planter")]:
        im = Image.open(raw / (source + ".png")).convert("RGB")
        assert np.asarray(im).std() > 15
        canvas = sheet(im.width + 48, im.height + 100, title)
        canvas.paste(im, (24, 58))
        path = DEST / (PREFIX + "room_" + source + ".png")
        canvas.save(path); files.append(path)
    for width in [360, 720]:
        im = Image.open(raw / ("entry_%d.png" % width)).convert("RGB")
        assert im.size == (width, round(width * 800 / 360))
        before = hashlib.sha256(np.asarray(im).tobytes()).hexdigest()
        meta = PngImagePlugin.PngInfo()
        meta.add_text("Author", "ZHAOYUN / \u8d75\u4e91")
        meta.add_text("Description", "SGODOT-319 N1 v1; native P0Room opening framing, 43 degrees, 6.72 m; no avatar or UI")
        path = DEST / (PREFIX + "entry_%d.png" % width)
        im.save(path, pnginfo=meta)
        assert hashlib.sha256(np.asarray(Image.open(path)).tobytes()).hexdigest() == before
        files.append(path)
    ref = DEST / "reference/SGODOT-315_Hotel_Lobby_Main_2026-10-31.png"
    canvas = sheet(2048, 1100, "Stark approved design / Godot N1 | Furniture retains full game scale")
    for i, (path, label) in enumerate([(ref, "STARK R3"), (raw / "full.png", "GODOT MOBILE / 43 DEGREES")]):
        x = 24 + 1010 * i
        ImageDraw.Draw(canvas).text((x, 64), label, fill="#293330", font=font(20))
        im = fit(Image.open(path), (986, 940))
        canvas.paste(im, (x + (986 - im.width) // 2, 102 + (940 - im.height) // 2))
    path = DEST / (PREFIX + "room_reference.png")
    canvas.save(path); files.append(path)
    canvas = sheet(2048, 1050, "Five local lights on / off | Same sun, camera and materials")
    for i, label in enumerate(["on", "off"]):
        x = 24 + i * 1010
        ImageDraw.Draw(canvas).text((x, 64), "LOCAL LIGHTS " + label.upper(), fill="#293330", font=font(20))
        im = fit(Image.open(raw / ("local_lights_" + label + ".png")), (986, 900))
        canvas.paste(im, (x, 103))
    path = DEST / (PREFIX + "local_lights.png")
    canvas.save(path); files.append(path)
    layout_image = Image.open(QA / "plan/full-size-plan.png")
    canvas = sheet(layout_image.width + 48, layout_image.height + 100, "Technical clearance | 0.70 m main route and 16 standing positions")
    canvas.paste(layout_image, (24, 58))
    path = DEST / (PREFIX + "clearance.png")
    canvas.save(path); files.append(path)
    a = np.asarray(Image.open(raw / "fire_a.png").convert("RGB"), dtype=float)
    b = np.asarray(Image.open(raw / "fire_b.png").convert("RGB"), dtype=float)
    fire_mask = (a[:, :, 0] > 150) & (a[:, :, 0] > a[:, :, 1] * 1.35)
    change = np.max(np.abs(a - b), axis=2)
    fire_check = {"orange_pixels": int(fire_mask.sum()), "changed_orange_pixels": int(((change > 8) & fire_mask).sum()),
        "scope": "Two actual rendered fire times; unchanged shared effect, not new particle-authoring acceptance or a phone benchmark."}
    assert fire_check["orange_pixels"] > 100 and fire_check["changed_orange_pixels"] > 30
    skin = json.loads((KIT / "atlas_skin.json").read_text())
    palette = json.loads((HALL / "hall_palette.json").read_text())["slots"]
    colour_checks = []
    atlas = Image.open(KIT / "room_albedo_ao.png").convert("RGB")
    for role, value in skin["palette_overrides"].items():
        old = tuple(bytes.fromhex(palette[role]["hex_srgb"])); new = tuple(bytes.fromhex(value))
        h1 = colorsys.rgb_to_hsv(*(v / 255 for v in old))[0] * 360
        h2 = colorsys.rgb_to_hsv(*(v / 255 for v in new))[0] * 360
        delta = min(abs(h1 - h2), 360 - abs(h1 - h2))
        x, y, w, h = palette[role]["rect_px_top_left"]
        assert atlas.getpixel((x + w // 2, y + h // 2)) == new
        assert delta <= 10
        colour_checks.append({"role": role, "source_hex": palette[role]["hex_srgb"], "N1_hex": value, "hue_delta_degrees": delta})
    positions = np.array([p[::2] for p in plan["standing_16"]])
    distances = [float(np.linalg.norm(positions[i] - positions[j])) for i in range(16) for j in range(i)]
    assert len(positions) == 16 and min(distances) >= .55 - .0001
    previous = json.loads((DEST / "n1-validation.json").read_text()) if (DEST / "n1-validation.json").exists() else {}
    def evidence(filename, key):
        path = QA / filename
        return json.loads(path.read_text()) if path.exists() else previous[key]
    verification = {"geometry": geometry, "godot": runtime, "early_navigation": early, "layout_plan": plan,
        "native_camera": native, "runtime_restoration": evidence("native-camera-restoration.json", "runtime_restoration"),
        "shared_shell_naming": evidence("shell-naming-validation.json", "shared_shell_naming"), "fire_motion": fire_check,
        "skin_hue_checks": colour_checks, "standing_minimum_separation_m": min(distances),
        "atlas_sha256": digest(KIT / "room_albedo_ao.png"), "blend_sha256": digest(ROOT / "tools/art/source/poi_hotel_lobby/poi_hotel_lobby.blend"),
        "scope": "Desktop Godot Mobile/Vulkan art and collision validation only. No P2 wiring, Android/phone, multiplayer or release."}
    dump(DEST / "n1-validation.json", verification)
    dump(DEST / "native-camera-n1-v1.json", native)
    dump(DEST / "media-manifest-n1-v1.json", [{"name": p.name, "path": str(p.relative_to(ROOT)), "size": list(Image.open(p).size),
        "bytes": p.stat().st_size, "sha256": digest(p)} for p in files])
    for rel in ["assets/rooms/poi_hotel_lobby", "assets/rooms/_shared/shell_hall", "scenes/poi_hotel_lobby", "scenes/shell_hall"]:
        for file in (QA / "project" / rel).glob("*"):
            if file.suffix in [".import", ".uid"]: shutil.copy2(file, ROOT / rel / file.name)
    uid = QA / "project/review.gd.uid"
    if uid.exists(): shutil.copy2(uid, ROOT / "tools/art/review_hotel_lobby_319.gd.uid")
    stats = json.loads((KIT / "asset_stats.json").read_text())
    measurements = ["# N1 Module Measurements", "", "X width / Z depth / Y height, metres. Count includes placed instances in the room total.", "",
        "| Module | Triangles | Surfaces | Local Width x Depth x Height |", "|---|---:|---:|---|"]
    for row in stats["assets"]:
        lo, hi = geometry["assets"][row["name"]]["local_bounds"]
        dims = [hi[i] - lo[i] for i in [0, 2, 1]]
        measurements.append("| %s | %d | %d | %.4f x %.4f x %.4f |" % (row["name"], row["triangles"], row["surfaces"], *dims))
    (DEST / "n1-measurements.md").write_text("\n".join(measurements) + "\n")
    print("PACKAGED_N1", len(files), "images; fire pixels changed", fire_check["changed_orange_pixels"], "standing separation", min(distances))


if __name__ == "__main__": main()
