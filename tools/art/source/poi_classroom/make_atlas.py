"""Classroom skin of the fixed hall UV layout; no shared asset is overwritten."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
HALL = ROOT / "assets/rooms/_shared/shell_hall"
OUT = ROOT / "assets/rooms/poi_classroom"
COLORS = {
    "parquet": "C89E73", "plaster": "E8D8C0", "panel": "939D83",
    "cornice": "F2E6D1", "skirting": "D8CDB5", "window": "F4E9D6",
    "plaster_solid": "E8D8C0", "wainscot_solid": "939D83", "cornice_solid": "F2E6D1",
    "window_solid": "F4E9D6", "floor_solid": "C89E73", "wood_dark": "A67F56",
    "wood_mid": "CAAA7E", "oak": "BB9C78", "oak_light": "C0A582", "oak_edge": "D9B68B",
    "brass": "B98D44", "linen": "F0E8D6", "sky": "487594", "sage": "7B927C",
    "sage_dark": "536E62", "linen_green": "A9B79A", "porcelain": "FFF1D5",
    "petal": "CB947C", "leaf": "60894C", "leaf_light": "81A660", "leaf_dark": "446A3F",
    "terra": "BD885E", "terra_light": "D5A879", "soil": "766449", "cloth_green": "A2AC8C",
}

def main():
    palette = json.loads((HALL / "hall_palette.json").read_text())
    pixels = np.asarray(Image.open(HALL / "hall_albedo_ao.png").convert("RGB")).astype(float).copy()
    for key, slot in palette["slots"].items():
        old = np.array(list(bytes.fromhex(slot["hex_srgb"])), dtype=float)
        color = COLORS.get(key, slot["hex_srgb"])
        new = np.array(list(bytes.fromhex(color)), dtype=float)
        x, y, w, h = slot["rect_px_top_left"]
        shade = np.mean(pixels[y:y+h, x:x+w] / np.maximum(old, 1), axis=2)
        pixels[y:y+h, x:x+w] = np.clip(new * shade[..., None], 0, 255)
        slot["hex_srgb"] = color
    atlas = Image.fromarray(pixels.astype(np.uint8))
    # The skin contract permits replacing parquet with straight boards. The
    # shell's rotated UV has world X along -V, so horizontal image rows run Z.
    slot = palette["slots"]["parquet"]
    x, y, w, h = slot["safe_rect_px_top_left"]
    yy, xx = np.mgrid[0:h, 0:w]
    row = yy // 38
    joint = ((xx + (row % 3) * 106) % 318 < 2) | (yy % 38 < 2)
    tone = 1 + .022*np.sin(row*4.7) + .012*np.sin(xx*.08+row*3) + .008*np.sin(yy*1.9)
    tone[joint] *= .78
    rgb = np.array(list(bytes.fromhex(COLORS["parquet"])), dtype=float)
    tile = Image.fromarray(np.clip(rgb*tone[..., None], 0, 255).astype(np.uint8))
    atlas.paste(tile, (x, y))
    # Original miniature subject pictures, with no lettering.
    for key in ["print_portrait", "print_landscape"]:
        x,y,w,h = palette["slots"][key]["rect_px_top_left"]
        picture = Image.new("RGB", (w,h), "#DDDCC0"); d = ImageDraw.Draw(picture)
        d.rectangle((12,12,w-13,h-13), fill="#9EBAC0")
        d.ellipse((154,30,196,72), fill="#F3DB97")
        d.polygon([(12,175),(60,84),(125,167),(177,108),(244,171),(244,244),(12,244)], fill="#7C9973")
        d.polygon([(12,201),(84,155),(146,182),(218,152),(244,194),(244,244),(12,244)], fill="#4E745F")
        atlas.paste(picture,(x,y))
    OUT.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT / "room_albedo_ao.png")
    palette.update(atlas="room_albedo_ao.png", task="SGODOT-322", author="ZHAOYUN",
        source_sha256=hashlib.sha256((HALL/"hall_albedo_ao.png").read_bytes()).hexdigest(),
        notes=["Same hall UV slots; shared shell files unchanged.",
               "v1.1: furniture albedo lowered/warmed toward the E5C6A0 lit appearance requested in 322 c1ea2382/b4643b1a.",
               "Floor C89E73 reduces orange relative to v1 CF9B66; furniture/floor separation is reviewed in actual lighting.",
               "wood_mid/oak_edge are shared with the hall foundation and perimeter; keep their v1 colors.",
               "Sage 939D83 follows the main image; absent from the four-color palette.",
               "Parquet slot replaced by original straight-board bitmap; floor UV remains rotated 90 degrees.",
               "Furniture contact AO is scalar COLOR_0; no photographs, text or final lighting baked."])
    (OUT / "atlas_skin.json").write_text(json.dumps(palette,indent=2)+"\n")

if __name__ == "__main__": main()
