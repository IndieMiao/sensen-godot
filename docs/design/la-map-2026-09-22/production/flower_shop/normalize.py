"""Normalize the flower shop POI into a transparent production map sprite."""

from pathlib import Path
import hashlib
import json

from PIL import Image

ROOT = Path(__file__).resolve().parents[5]
WORK = Path(__file__).resolve().parent
DEST = ROOT / "assets/map/poi/flower_shop.png"

image = Image.open(WORK / "keyed.png").convert("RGBA")
# Both lavender clusters are wholly inside the opaque building/plant silhouette.
# Preserve their original opaque color where magenta spill cleanup also caught
# the intentionally purple petals. These rectangles contain no keyed backdrop.
raw = Image.open(WORK / "raw-magenta.png").convert("RGBA")
lavender_regions = ((330, 680, 435, 805), (650, 800, 780, 945))
for region in lavender_regions:
    image.paste(raw.crop(region), region)
image.save(WORK / "keyed-preserved-colors.png")
box = image.getchannel("A").getbbox()
if not box:
    raise ValueError("The extracted flower shop is empty")
crop = image.crop(box)
crop.thumbnail((448, 448), Image.Resampling.LANCZOS)
canvas = Image.new("RGBA", (512, 512))
offset = ((512 - crop.width) // 2, 480 - crop.height)
canvas.alpha_composite(crop, offset)
DEST.parent.mkdir(parents=True, exist_ok=True)
canvas.save(DEST)

for label, background in (("light", "#f1f5ed"), ("dark", "#283f3c")):
    preview = Image.new("RGBA", canvas.size, background)
    preview.alpha_composite(canvas)
    preview.convert("RGB").save(WORK / f"preview-{label}.png")

provenance = {
    "asset": str(DEST.relative_to(ROOT)),
    "source": "Sensenjoy Image API",
    "base_url": "https://sub.sensenjoy.cn/v1",
    "model": "gpt-image-2",
    "endpoint": "/images/edits",
    "quality": "high",
    "requested_size": [1024, 1024],
    "generated_size": list(image.size),
    "prompt": "prompt.txt",
    "actual_reference_inputs": ["reference-style-cafe.png", "assets/map/poi/restaurant.png"],
    "reference_source": "docs/design/la-map-2026-09-22/generated/la-map-main-v1.png",
    "reference_crop_pixels": [190, 793, 355, 968],
    "raw_output": "raw-magenta.png",
    "keyed_output": "keyed.png",
    "color_preserved_output": "keyed-preserved-colors.png",
    "opaque_lavender_restore_regions": list(lavender_regions),
    "chroma_key": "#FF00FF",
    "extraction": "imagegen bundled remove_chroma_key.py, soft matte thresholds 64/128 and spill cleanup",
    "production_size": [512, 512],
    "source_alpha_bbox": list(box),
    "production_alpha_bbox": list(canvas.getchannel("A").getbbox()),
    "bottom_center_anchor_pixels": [256, 480],
    "bottom_center_anchor_normalized": [0.5, 0.9375],
    "sha256": hashlib.sha256(DEST.read_bytes()).hexdigest(),
}
(WORK / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
print(json.dumps(provenance, indent=2))
