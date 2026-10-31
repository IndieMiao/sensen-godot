"""Package inspected Godot shell views and exact atlas swatches for SGODOT-319."""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / "assets/rooms/_shared/shell_hall"
QA = ROOT / "output/poi-hall-319"
DEST = ROOT / "docs/design/poi-hotel-lobby-319-2026-10-31"
PREFIX = "SGODOT-319_N1_v1_"
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
INK, BG = "#293330", "#F5F5F2"


def font(size): return ImageFont.truetype(FONT, size)


def write_json(path, value): path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def canvas(width, height, title):
    image = Image.new("RGB", (width, height), BG)
    ImageDraw.Draw(image).text((24, 14), title, fill=INK, font=font(25))
    return image


def save(image, suffix):
    ImageDraw.Draw(image).text((24, image.height - 36), "SGODOT-319 | ZHAOYUN / \u8d75\u4e91 | SHARED SHELL v1 | 2026-10-31", fill=INK, font=font(19))
    path = DEST / (PREFIX + suffix + ".png")
    image.save(path)
    return path


def fit(image, box):
    image = image.copy()
    image.thumbnail(box, Image.Resampling.LANCZOS)
    return image


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    captures = QA / "captures"
    geometry = json.loads((QA / "geometry-validation.json").read_text())
    runtime = json.loads((captures / "godot-validation.json").read_text())
    assert geometry["passed"] and runtime["passed"] and runtime["physics_complete"]
    assert "SCRIPT ERROR" not in (QA / "render.log").read_text()
    manifest = []
    for source, suffix, title in [
        ("shell_full", "shell_full", "Shared hall shell | 43-degree full view | No hotel furniture"),
        ("shell_top", "shell_top", "Shared hall shell | Top | 6.8 x 6.4 m"),
        ("window_detail", "shell_window", "Window module | Separate casing, grille and glass"),
    ]:
        raw = Image.open(captures / (source + ".png")).convert("RGB")
        assert np.asarray(raw).std() > 15
        image = canvas(raw.width + 48, raw.height + 100, title)
        image.paste(raw, (24, 58))
        manifest.append(save(image, suffix))
    image = canvas(2048, 1460, "Shared hall shell | Front, right, back, left | Orthographic elevations")
    draw = ImageDraw.Draw(image)
    for i, name in enumerate(["front", "right", "back", "left"]):
        x, y = 24 + i % 2 * 1000, 70 + i // 2 * 675
        draw.text((x, y), name.upper(), fill=INK, font=font(21))
        view = fit(Image.open(captures / ("shell_" + name + ".png")), (976, 628))
        image.paste(view, (x, y + 34))
    manifest.append(save(image, "shell_four_sides"))
    palette = json.loads((KIT / "hall_palette.json").read_text())
    atlas = Image.open(KIT / "hall_albedo_ao.png").convert("RGB")
    colors = []
    for role, slot in palette["slots"].items():
        if slot["kind"] != "solid_reuse_swatch": continue
        x, y, w, h = slot["rect_px_top_left"]
        expected = tuple(bytes.fromhex(slot["hex_srgb"]))
        actual = atlas.getpixel((x + w // 2, y + h // 2))
        assert actual == expected, (role, actual, expected)
        colors.append({"role": role, "hex": slot["hex_srgb"], "rgb8": list(actual), "exact": True})
    image = canvas(1680, 1200, "Hall atlas contract v1 | 2048 x 2048 | Fixed regions and 32 reserved swatches")
    draw = ImageDraw.Draw(image)
    image.paste(atlas.resize((800, 800), Image.Resampling.LANCZOS), (24, 74))
    draw.text((24, 896), "6 shell regions above; 32 reusable color tiles below.", fill=INK, font=font(22))
    draw.text((24, 938), "16 px safe gutter. PNG and glTF origin: top-left.", fill=INK, font=font(22))
    draw.text((24, 980), "hall_palette.json includes all 16 mappings from PR #563.", fill=INK, font=font(22))
    for i, row in enumerate(colors):
        x, y = 856 + i % 2 * 400, 70 + i // 2 * 65
        draw.rectangle((x, y + 6, x + 54, y + 52), fill="#" + row["hex"], outline="#B8BFBB", width=1)
        draw.text((x + 66, y), row["role"], fill=INK, font=font(19))
        draw.text((x + 66, y + 28), "#" + row["hex"], fill="#60706A", font=font(17))
    manifest.append(save(image, "shell_palette"))
    md = ["# Hall Atlas Regions", "", "SGODOT-319 / ZHAOYUN. PNG and glTF UV origin: top-left. Rectangles are x, y, width, height.", "",
        "| Role | Base sRGB | Region px | Safe glTF UV min/max | Kind |", "|---|---|---|---|---|"]
    for role, slot in palette["slots"].items():
        md.append(f'| {role} | #{slot["hex_srgb"]} | {slot["rect_px_top_left"]} | {slot["uv_rect_gltf"]} | {slot["kind"]} |')
    (DEST / "atlas-regions.md").write_text("\n".join(md) + "\n")
    reference_dir = DEST / "reference"
    reference_dir.mkdir(exist_ok=True)
    for filename in ["SGODOT-315_Hotel_Lobby_Main_2026-10-31.png", "SGODOT-315_R3_topdown.svg"]:
        source = Path.home() / "incoming/poi-r3/315" / filename
        if source.exists(): shutil.copy2(source, reference_dir / filename)
    reference = reference_dir / "SGODOT-315_Hotel_Lobby_Main_2026-10-31.png"
    assert reference.exists()
    image = canvas(2048, 1110, "Stark approved N1 design / Shared shell stage | Furniture follows shell review")
    for i, (path, title) in enumerate([(reference, "APPROVED STARK MAIN"), (captures / "shell_full.png", "GODOT SHARED SHELL ONLY")]):
        x = 24 + i * 1010
        ImageDraw.Draw(image).text((x, 66), title, fill=INK, font=font(20))
        view = fit(Image.open(path), (986, 950))
        image.paste(view, (x + (986 - view.width) // 2, 105 + (950 - view.height) // 2))
    manifest.append(save(image, "shell_reference"))
    image = canvas(2048, 1050, "Directional daylight on / off | Identical camera and atlas")
    for i, name in enumerate(["sun_on", "sun_off"]):
        x = 24 + i * 1010
        ImageDraw.Draw(image).text((x, 65), name.upper().replace("_", " "), fill=INK, font=font(20))
        view = fit(Image.open(captures / (name + ".png")), (986, 904))
        image.paste(view, (x, 103))
    manifest.append(save(image, "shell_daylight"))
    runtime["scope"] = "Desktop Vulkan Mobile art assembly and capsule sweeps; no Android or multiplayer claims."
    validation = {"geometry": geometry, "godot": runtime, "atlas_swatch_readback": colors,
        "reference_sha256": hashlib.sha256(reference.read_bytes()).hexdigest()}
    write_json(DEST / "validation.json", validation)
    write_json(DEST / "media-manifest.json", [{"name": path.name, "path": str(path.relative_to(ROOT)),
        "size": list(Image.open(path).size), "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in manifest])
    for source in (QA / "project" / "assets/rooms/_shared/shell_hall").glob("*.import"):
        shutil.copy2(source, KIT / source.name)
    uid = QA / "project/scenes/shell_hall/shell_hall_art.gd.uid"
    if uid.exists(): shutil.copy2(uid, ROOT / "scenes/shell_hall/shell_hall_art.gd.uid")
    uid = QA / "project/review.gd.uid"
    if uid.exists(): shutil.copy2(uid, ROOT / "tools/art/review_shell_hall_319.gd.uid")
    print("PACKAGED", len(manifest), "images;", len(colors), "exact atlas swatches")


if __name__ == "__main__": main()
