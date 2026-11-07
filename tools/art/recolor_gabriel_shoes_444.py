#!/usr/bin/env python3
"""Copy shoes3 FBX exactly; recolor only its cyan texture region for Gabriel."""
from pathlib import Path
import hashlib
import json
import shutil
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DONOR = ROOT / "assets/avatar/source/shoes3"
TARGET = ROOT / "assets/avatar/source/shoes3_npc_gabriel"
REPORT = ROOT / "docs/design/npc-gabriel-444/dark-shoes-v1.4"
TARGET.mkdir(parents=True, exist_ok=True)
REPORT.mkdir(parents=True, exist_ok=True)

texture = "T_skin03_shoes_D.png"
fbx = "SK_dt_skin03.fbx"
source = np.array(Image.open(DONOR / texture).convert("RGBA"))
rgb = source[:, :, :3].astype(np.int16)
# Include the antialiased cyan boundary; all other donor colors have R >= G/B.
mask = (rgb[:, :, 1] > rgb[:, :, 0]) & (rgb[:, :, 2] > rgb[:, :, 0])
out = source.copy()
shade = np.rint(np.clip(60 + (rgb[:, :, 0] - 154) * 0.04, 58, 61)).astype(np.uint8)
out[mask, 0] = shade[mask]
out[mask, 1] = shade[mask] - 1
out[mask, 2] = shade[mask] - 1
Image.fromarray(out).save(TARGET / texture)
shutil.copyfile(DONOR / fbx, TARGET / fbx)

# Copy parameters only; Godot creates independent UIDs and path remaps.
for name, importer, resource in [(texture, "texture", "CompressedTexture2D"), (fbx, "scene", "PackedScene")]:
    side = TARGET / (name + ".import")
    if not side.exists():
        params = (DONOR / (name + ".import")).read_text().split("[params]", 1)[1]
        side.write_text(f'[remap]\nimporter="{importer}"\ntype="{resource}"\n\n[params]' + params)

sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
report = {
    "donor": str(DONOR.relative_to(ROOT)),
    "target": str(TARGET.relative_to(ROOT)),
    "source_size": [source.shape[1], source.shape[0]],
    "cyan_pixels": int(mask.sum()),
    "changed_percent": float(mask.mean() * 100),
    "mask": "G > R and B > R, including antialiased boundary",
    "replacement_rgb_min": out[mask, :3].min(axis=0).tolist(),
    "replacement_rgb_max": out[mask, :3].max(axis=0).tolist(),
    "outside_mask_exact": bool(np.array_equal(source[~mask], out[~mask])),
    "alpha_exact": bool(np.array_equal(source[:, :, 3], out[:, :, 3])),
    "fbx_byte_identical": (DONOR / fbx).read_bytes() == (TARGET / fbx).read_bytes(),
    "source_import_note": "Unmodified FBX retains four missing unused full-outfit texture references. No aliases or path fixes, per art director; runtime uses the recipe albedo.",
    "donor_sha256": {p.name: sha(p) for p in sorted(DONOR.iterdir()) if p.is_file()},
    "output_png_sha256": sha(TARGET / texture),
}
assert report["outside_mask_exact"] and report["alpha_exact"] and report["fbx_byte_identical"]
(REPORT / "texture-validation.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
