#!/usr/bin/env python3
"""Recolor cloth1 for Ivo; run from the art branch against a runtime checkout."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

ART_ROOT = Path(__file__).resolve().parents[2]


def remap(pixels, mask, colors):
    luminance = pixels[..., :3].astype(float) @ np.array([0.2126, 0.7152, 0.0722])
    values = luminance[mask]
    knots = [float(values.min()), float(np.median(values)), float(values.max())]
    # The shirt is mostly one flat source color. Keep that plateau at the
    # requested midtone, rather than mapping it to the shadow endpoint.
    if knots[0] == knots[1]:
        knots[0] = knots[1] * 0.75
    if knots[1] == knots[2]:
        knots[2] = min(255.0, knots[1] * 1.15)
    palette = np.array([[int(c[i:i + 2], 16) for i in (0, 2, 4)] for c in colors])
    mapped = np.rint(np.stack([
        np.interp(luminance, knots, palette[:, channel]) for channel in range(3)
    ], axis=-1)).astype(np.uint8)
    return mapped, {"luminance_knots": knots, "source_luminance_range": [float(values.min()), float(values.max())], "palette_shadow_mid_highlight": colors}


def run():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", type=Path, required=True)
    args = parser.parse_args()
    source = args.runtime_root / "assets/avatar/source/cloth1"
    dest = args.runtime_root / "assets/avatar/source/cloth1_npc_ivo"
    dest.mkdir(parents=True, exist_ok=True)
    fbx = "SK_dt_skin01.fbx"
    texture = "T_ivo_cloth_D.png"
    shutil.copy2(source / fbx, dest / fbx)
    pixels = np.array(Image.open(source / "T_skin01_cloth_D 1.png").convert("RGBA"))
    rgb = pixels[..., :3].astype(float)
    shirt = (rgb[..., 0] - rgb[..., 2] > 15) & (rgb[..., 1] - rgb[..., 2] > 15)
    shorts = (rgb.max(axis=-1) < 125) & ~shirt
    details = ~(shirt | shorts)
    output = pixels.copy()
    report = {}
    for name, mask, colors in [
        ("shirt", shirt, ["7A5E3E", "9C7A52", "B8966A"]),
        ("shorts", shorts, ["26231F", "3A3632", "55504A"]),
    ]:
        mapped, info = remap(pixels, mask, colors)
        output[..., :3][mask] = mapped[mask]
        info.update(pixel_count=int(mask.sum()), fraction=float(mask.mean()), output_unique_colors=len(np.unique(mapped[mask], axis=0)))
        report[name] = info
    Image.fromarray(output).save(dest / texture)
    for original, target in [(fbx, fbx), ("T_skin01_cloth_D 1.png", texture)]:
        sidecar = dest / (target + ".import")
        if not sidecar.exists():
            params = (source / (original + ".import")).read_text().split("[params]\n", 1)[1]
            importer, resource = ("scene", "PackedScene") if target.endswith(".fbx") else ("texture", "CompressedTexture2D")
            sidecar.write_text(f'[remap]\nimporter="{importer}"\ntype="{resource}"\n\n[params]\n' + params)
    report.update(
        id="cloth1_npc_ivo", base="cloth1", source_pixels=[pixels.shape[1], pixels.shape[0]],
        details_pixel_count=int(details.sum()), details_fraction=float(details.mean()),
        details_byte_identical=bool(np.array_equal(output[details], pixels[details])),
        alpha_exact=bool(np.array_equal(output[..., 3], pixels[..., 3])),
        fbx_byte_identical=(source / fbx).read_bytes() == (dest / fbx).read_bytes(),
        sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [dest / fbx, dest / texture]},
    )
    path = ART_ROOT / "tools/art/source/resident_parts_284/ivo-cloth-texture-validation.json"
    path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    run()
