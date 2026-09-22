"""Chroma-key raw icons and write 256px WebP map icons (bottom anchor y=240/256)."""
import json, hashlib
from pathlib import Path
import numpy as np
from PIL import Image
ROOT = Path("/Volumes/ACASIS/projects/sensen-godot")
DEST = ROOT / "assets/map/poi/icons"
DEST.mkdir(parents=True, exist_ok=True)
out = {}
for raw in sorted(Path(".").glob("raw-*.png")):
    name = raw.stem[4:]
    a = np.asarray(Image.open(raw).convert("RGBA"), dtype=np.float32)
    r, g, b, sa = a[..., 0], a[..., 1], a[..., 2], a[..., 3] / 255
    dist = np.sqrt((r - 255) ** 2 + g ** 2 + (b - 255) ** 2)
    matte = np.clip((dist - 64) / 64, 0, 1)
    alpha = np.minimum(matte, sa)
    spill = np.clip(np.minimum(r, b) - g, 0, None) * (1 - matte)
    edge = (matte < 1) & (sa > 0)
    rgba = np.stack([np.where(edge, r - spill, r), g, np.where(edge, b - spill, b), alpha * 255], -1).clip(0, 255).astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA")
    box = img.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    crop = img.crop(box)
    crop.thumbnail((224, 224), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (256, 256))
    canvas.alpha_composite(crop, ((256 - crop.width) // 2, 240 - crop.height))
    dest = DEST / f"{name}.webp"
    canvas.save(dest, "WEBP", quality=90, method=6)
    out[name] = {"asset": str(dest.relative_to(ROOT)), "bytes": dest.stat().st_size, "sha256": hashlib.sha256(dest.read_bytes()).hexdigest()}
Path("provenance.json").write_text(json.dumps(out, indent=2) + "\n")
print(len(out), "icons,", sum(v["bytes"] for v in out.values()) // 1024, "KB total")
