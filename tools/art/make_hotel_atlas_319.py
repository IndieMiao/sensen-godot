"""N1 skin of the approved hall atlas; fixed regions, original small bitmap details."""
from pathlib import Path
import hashlib
import json
import math
import re

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
HALL = ROOT / "assets/rooms/_shared/shell_hall"
OUT = ROOT / "assets/rooms/poi_hotel_lobby"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    atlas = Image.open(HALL / "hall_albedo_ao.png").convert("RGB")
    palette = json.loads((HALL / "hall_palette.json").read_text())["slots"]
    changed = []
    overrides = {"wood_dark": "783B22", "cloth_green": "42683A", "stone": "C8C3B9"}
    for role in ["wood_dark", "stone"]:
        x, y, w, h = palette[role]["rect_px_top_left"]
        atlas.paste(Image.new("RGB", (w, h), "#" + overrides[role]), (x, y))
        changed.append({"role": role, "rect_px": [x, y, w, h], "override_hex": overrides[role]})
    def tile(role, paint, keep_center=False):
        x, y, w, h = palette[role]["rect_px_top_left"]
        image = Image.new("RGB", (w, h), "#" + palette[role]["hex_srgb"])
        paint(image)
        if keep_center:
            ImageDraw.Draw(image).rectangle((w // 2 - 12, h // 2 - 12, w // 2 + 12, h // 2 + 12), fill="#" + overrides.get(role, palette[role]["hex_srgb"]))
        atlas.paste(image, (x, y))
        changed.append({"role": role, "rect_px": [x, y, w, h]})
    def rug(image):
        draw = ImageDraw.Draw(image)
        for i in range(-300, 512, 22):
            draw.line((i, 0, i + 256, 256), fill="#304E29", width=1)
            draw.line((i, 0, i - 256, 256), fill="#35512C", width=1)
        for inset in [9, 14]: draw.rectangle((inset, inset, 255 - inset, 255 - inset), outline="#B7914F", width=2)
    tile("cloth_green", rug, True)
    def hide(image):
        yy, xx = np.mgrid[0:256, 0:256]
        x, y = xx / 256, yy / 256
        field = np.sin(x * 15 + np.sin(y * 9)) + .7 * np.cos(y * 17 + x * 4) + .35 * np.sin((x - y) * 31)
        edge = np.minimum(np.minimum(x, 1 - x), np.minimum(y, 1 - y))
        mask = np.clip((field + .12) * 3, 0, 1) * np.clip((edge - .05) * 8, 0, 1)
        cream = np.array([238, 226, 202]); brown = np.array([133, 72, 39])
        rgb = cream[None, None, :] * (1 - mask[:, :, None]) + brown[None, None, :] * mask[:, :, None]
        image.paste(Image.fromarray(rgb.astype(np.uint8)))
    tile("print_portrait", hide)
    def landscape(image):
        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 0, 255, 255), fill="#D7D9BE")
        draw.polygon([(0, 125), (50, 76), (97, 111), (155, 72), (255, 109), (255, 255), (0, 255)], fill="#85957B")
        draw.polygon([(0, 175), (56, 136), (113, 148), (170, 119), (255, 135), (255, 255), (0, 255)], fill="#5D7453")
        draw.polygon([(105, 151), (144, 145), (190, 255), (85, 255), (131, 192)], fill="#B8BCA0")
        for x, y, s in [(20, 125, 30), (61, 148, 23), (205, 131, 31), (236, 164, 29)]:
            draw.line((x, y, x, y + s * 2), fill="#61583A", width=4)
            for i in range(4): draw.ellipse((x - s * .6 + i * 3, y - s * .4 + i * s * .22, x + s * .5, y + s * .65 + i * s * .17), fill=["#526C42", "#6B814B", "#7C8E53", "#5E783F"][i])
        image.paste(image.filter(ImageFilter.GaussianBlur(.6)))
    tile("print_landscape", landscape)
    def mirror(image):
        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 0, 255, 255), fill="#A7B4AB")
        draw.polygon([(0, 164), (80, 108), (255, 170), (255, 255), (0, 255)], fill="#A5825E")
        draw.polygon([(0, 0), (55, 0), (255, 182), (255, 238)], fill="#DCE4D8")
        draw.rounded_rectangle((71, 139, 151, 252), radius=20, fill="#E9DEC8")
        draw.rectangle((40, 0, 48, 255), fill="#84958C")
        image.paste(image.filter(ImageFilter.GaussianBlur(3)))
    tile("sky", mirror)
    atlas.save(OUT / "room_albedo_ao.png")
    path = OUT / "room_albedo_ao.png.import"
    if not path.exists():
        rel = "res://assets/rooms/poi_hotel_lobby/room_albedo_ao.png"
        template = (HALL / "hall_albedo_ao.png.import").read_text()
        template = re.sub(r'uid="[^\"]+"\n', "", template)
        template = template.replace("res://assets/rooms/_shared/shell_hall/hall_albedo_ao.png", rel)
        template = re.sub(r"hall_albedo_ao.png-[a-f0-9]+", "room_albedo_ao.png-" + hashlib.md5(rel.encode()).hexdigest(), template)
        path.write_text(template)
    (OUT / "atlas_skin.json").write_text(json.dumps({"base": "assets/rooms/_shared/shell_hall/hall_albedo_ao.png",
        "base_sha256": hashlib.sha256((HALL / "hall_albedo_ao.png").read_bytes()).hexdigest(), "same_uv_layout": True,
        "changed_regions": changed, "palette_overrides": overrides, "shell_regions_unchanged": True,
        "override_reason": "Keep source hue families while matching shaded furniture readability under native P0 ACES lighting; cloth tile center alone is the sofa swatch.",
        "purpose": "Original miniature landscape, rug weave, hide markings and static mirror impression; no extra room texture."}, indent=2) + "\n")
    print("N1_ATLAS", len(changed), "detail regions")


if __name__ == "__main__": main()
