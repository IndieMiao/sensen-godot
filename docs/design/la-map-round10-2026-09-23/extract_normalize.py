"""Chroma-key the raw magenta renders and normalize into production POI variants.

Follows the shipped pipeline (docs/design/la-map-2026-09-22/production/*):
soft matte on distance to #FF00FF (thresholds 64/128), spill cleanup on edges,
alpha-bbox crop, Lanczos fit 448x448, ground at y=480 on a 512 RGBA canvas.
"""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path("/Volumes/ACASIS/projects/sensen-godot")
DEST_DIR = ROOT / "assets/map/poi"
SOFT_LO, SOFT_HI = 64.0, 128.0

def key_out(raw_path: Path) -> Path:
    img = np.asarray(Image.open(raw_path).convert("RGBA"), dtype=np.float32)
    r, g, b, src_a = img[..., 0], img[..., 1], img[..., 2], img[..., 3] / 255.0
    dist = np.sqrt((r - 255.0) ** 2 + g ** 2 + (b - 255.0) ** 2)
    matte = np.clip((dist - SOFT_LO) / (SOFT_HI - SOFT_LO), 0.0, 1.0)
    # The API may return either a magenta backdrop or true transparency;
    # honor both: keep a pixel only where the source alpha AND the matte keep it.
    alpha = np.minimum(matte, src_a)
    # Spill cleanup: pull magenta cast out of semi-transparent edge pixels.
    edge = (matte < 1.0) & (src_a > 0.0)
    spill = np.clip(np.minimum(r, b) - g, 0.0, None) * (1.0 - matte)
    r2 = np.where(edge, r - spill, r)
    b2 = np.where(edge, b - spill, b)
    out = np.stack([r2, g, b2, alpha * 255.0], axis=-1).astype(np.uint8)
    keyed = Image.fromarray(out, "RGBA")
    keyed_path = raw_path.with_name(raw_path.name.replace("raw-", "keyed-"))
    keyed.save(keyed_path)
    return keyed_path

def normalize(keyed_path: Path, name: str) -> dict:
    image = Image.open(keyed_path).convert("RGBA")
    box = image.getchannel("A").getbbox()
    if not box:
        raise ValueError(f"{name}: extracted image is empty")
    crop = image.crop(box)
    crop.thumbnail((448, 448), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (512, 512))
    canvas.alpha_composite(crop, ((512 - crop.width) // 2, 480 - crop.height))
    dest = DEST_DIR / f"{name}.png"
    canvas.save(dest)
    for label, background in (("light", "#f1f5ed"), ("dark", "#283f3c")):
        preview = Image.new("RGBA", canvas.size, background)
        preview.alpha_composite(canvas)
        preview.convert("RGB").save(keyed_path.with_name(f"preview-{name}-{label}.png"))
    return {
        "asset": str(dest.relative_to(ROOT)),
        "source": "Sensenjoy Image API",
        "base_url": "https://sub.sensenjoy.cn/v1",
        "model": "gpt-image-2",
        "endpoint": "/images/edits",
        "quality": "high",
        "prompt": f"prompt-{name}.txt",
        "reference_inputs": [
            "docs/design/la-map-2026-09-22/production/restaurant/reference-style-cafe.png",
            f"assets/map/poi/{name.rsplit('_', 1)[0]}.png"],
        "chroma_key": "#FF00FF",
        "extraction": "soft matte thresholds 64/128 with edge spill cleanup",
        "production_size": [512, 512],
        "bottom_center_anchor_pixels": [256, 480],
        "sha256": hashlib.sha256(dest.read_bytes()).hexdigest(),
    }

if __name__ == "__main__":
    provenance = {}
    for raw in sorted(Path(".").glob("raw-*.png")):
        name = raw.stem.replace("raw-", "")
        provenance[name] = normalize(key_out(raw), name)
        print("done", name)
    Path("provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print("all", len(provenance))
