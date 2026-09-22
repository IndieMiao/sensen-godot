"""Normalize the keyed Hollywood landmark into its production map sprite."""

from pathlib import Path
import hashlib
import json

from PIL import Image


ROOT = Path(__file__).resolve().parents[5]
WORK = Path(__file__).resolve().parent
DEST = ROOT / "assets/map/poi/hollywood_sign.png"

image = Image.open(WORK / "keyed.png").convert("RGBA")
box = image.getchannel("A").getbbox()
if not box:
    raise ValueError("The extracted landmark is empty")
crop = image.crop(box)
crop.thumbnail((464, 464), Image.Resampling.LANCZOS)
canvas = Image.new("RGBA", (512, 512))
offset = ((512 - crop.width) // 2, 488 - crop.height)
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
    "actual_reference_input": "reference-hollywood.png",
    "reference_source": "docs/design/la-map-2026-09-22/generated/la-map-main-v1.png",
    "reference_crop_pixels": [212, 254, 555, 396],
    "raw_output": "raw-magenta.png",
    "keyed_output": "keyed.png",
    "chroma_key": "#FF00FF",
    "extraction": "imagegen bundled remove_chroma_key.py, soft matte thresholds 64/128 and spill cleanup",
    "production_size": [512, 512],
    "source_alpha_bbox": list(box),
    "production_alpha_bbox": list(canvas.getchannel("A").getbbox()),
    "bottom_center_anchor_pixels": [256, 488],
    "bottom_center_anchor_normalized": [0.5, 0.953125],
    "sha256": hashlib.sha256(DEST.read_bytes()).hexdigest(),
}
(WORK / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
print(json.dumps(provenance, indent=2))
