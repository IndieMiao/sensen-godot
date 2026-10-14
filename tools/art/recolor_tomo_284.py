#!/usr/bin/env python3
"""Tomo's texture-only hairhat0 variant; preserve the original FBX verbatim."""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/avatar/source/hairhat0"
DEST = ROOT / "assets/avatar/source/hairhat0_npc_tomo"
REPORT = ROOT / "tools/art/source/resident_parts_284/tomo-texture-validation.json"


def run():
    DEST.mkdir(parents=True, exist_ok=True)
    fbx = "SM_hairHat0.fbx"
    texture = "T_tomo_hairHat_D.png"
    shutil.copy2(SOURCE / fbx, DEST / fbx)
    pixels = np.array(Image.open(SOURCE / "T_base_boy_hairHat_D.png").convert("RGBA"))
    # Inspected source: only neutral hair islands, no hat/accessory regions.
    # Map all source luminances monotonically, without percentile clipping,
    # retaining baked strand highlights/shadows and the original alpha.
    lum = pixels[..., :3].astype(float) @ np.array([0.2126, 0.7152, 0.0722])
    knots = np.array([lum.min(), np.median(lum), lum.max()])
    assert knots[0] < knots[1] < knots[2]
    palette = np.array([[46, 31, 22], [74, 51, 36], [107, 76, 54]])
    output = pixels.copy()
    output[..., :3] = np.rint(np.stack([
        np.interp(lum, knots, palette[:, channel]) for channel in range(3)
    ], axis=-1)).astype(np.uint8)
    Image.fromarray(output).save(DEST / texture)
    # Copy import parameters only: Godot assigns fresh path hashes and UIDs.
    for original, target in [(fbx, fbx), ("T_base_boy_hairHat_D.png", texture)]:
        sidecar = DEST / (target + ".import")
        if not sidecar.exists():
            params = (SOURCE / (original + ".import")).read_text().split("[params]\n", 1)[1]
            importer, resource = ("scene", "PackedScene") if target.endswith(".fbx") else ("texture", "CompressedTexture2D")
            sidecar.write_text(f'[remap]\nimporter="{importer}"\ntype="{resource}"\n\n[params]\n' + params)
    report = {
        "base": "hairhat0", "id": "hairhat0_npc_tomo",
        "source_pixels": [pixels.shape[1], pixels.shape[0]],
        "luminance_knots_min_median_max": knots.tolist(),
        "palette_shadow_mid_highlight": ["#2E1F16", "#4A3324", "#6B4C36"],
        "alpha_exact": bool(np.array_equal(pixels[..., 3], output[..., 3])),
        "output_unique_colors": len(np.unique(output[..., :3].reshape(-1, 3), axis=0)),
        "non_hair_regions": "None: inspected source contains only hair islands.",
        "fbx_byte_identical": (SOURCE / fbx).read_bytes() == (DEST / fbx).read_bytes(),
        "sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [DEST / fbx, DEST / texture]},
    }
    REPORT.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    run()
