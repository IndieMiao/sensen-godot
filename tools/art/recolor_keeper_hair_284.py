#!/usr/bin/env python3
"""SGODOT-284 keeper hair: recolor hair pixels; preserve FBX/accessories verbatim."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

ART_ROOT = Path(__file__).resolve().parents[2]
VARIANTS = [
    ("hairhat41", "hairhat41_npc_auburn", "SM_hairHat41.fbx",
     "T_skin33_hairHat_D.png", "T_auburn_hairHat41_D.png",
     ["5E2F1C", "8A4A2E", "B06A45"]),
    ("hairhat43", "hairhat43_npc_black", "SM_hairHat43.fbx",
     "T_skin35_hairHat_D.png", "T_black_hairHat43_D.png",
     ["161312", "2A2624", "4A4440"]),
]


def run():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", type=Path, required=True)
    args = parser.parse_args()
    reports = []
    for base, part_id, fbx, source_png, target_png, colors in VARIANTS:
        source = args.runtime_root / "assets/avatar/source" / base
        dest = args.runtime_root / "assets/avatar/source" / part_id
        dest.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / fbx, dest / fbx)
        original = np.array(Image.open(source / source_png).convert("RGBA"))
        rgb = original[..., :3].astype(float)
        red, green, blue = rgb.transpose(2, 0, 1)
        # Inspected atlases have disjoint color families with hard island edges.
        # 41: dark, low-chroma brown hair; ochre has R-G >=32 and pale details
        # are brighter. Include the darkest baked hair creases as well.
        # 43: yellow hair has G-B >30; pink accessory pixels have G~B.
        mask = ((red < 128) & (red - green < 20)) if base == "hairhat41" else (green - blue > 30)
        luminance = rgb @ np.array([0.2126, 0.7152, 0.0722])
        values = luminance[mask]
        knots = [float(values.min()), float(np.median(values)), float(values.max())]
        assert knots[0] < knots[1] < knots[2]
        palette = np.array([[int(c[i:i + 2], 16) for i in (0, 2, 4)] for c in colors])
        mapped = np.rint(np.stack([
            np.interp(values, knots, palette[:, channel]) for channel in range(3)
        ], axis=-1)).astype(np.uint8)
        result = original.copy()
        result[..., :3][mask] = mapped
        Image.fromarray(result).save(dest / target_png)
        # Preserve parameters, but let Godot assign new UIDs/path hashes.
        for original_name, target_name in [(fbx, fbx), (source_png, target_png)]:
            sidecar = dest / (target_name + ".import")
            if not sidecar.exists():
                params = (source / (original_name + ".import")).read_text().split("[params]\n", 1)[1]
                importer, resource = ("scene", "PackedScene") if target_name.endswith(".fbx") else ("texture", "CompressedTexture2D")
                sidecar.write_text(f'[remap]\nimporter="{importer}"\ntype="{resource}"\n\n[params]\n' + params)
        reports.append({
            "base": base, "id": part_id,
            "source_pixels": [original.shape[1], original.shape[0]],
            "mask_rule": "R < 128 and R-G < 20" if base == "hairhat41" else "G-B > 30",
            "hair_pixel_count": int(mask.sum()), "hair_fraction": float(mask.mean()),
            "preserved_pixel_count": int((~mask).sum()),
            "non_hair_rgba_exact": bool(np.array_equal(original[~mask], result[~mask])),
            "alpha_exact": bool(np.array_equal(original[..., 3], result[..., 3])),
            "luminance_knots_min_median_max": knots,
            "palette_shadow_mid_highlight": ["#" + c for c in colors],
            "output_hair_unique_colors": len(np.unique(mapped, axis=0)),
            "monotone_luminance_mapping": True,
            "fbx_byte_identical": (source / fbx).read_bytes() == (dest / fbx).read_bytes(),
            "sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in [dest / fbx, dest / target_png]},
        })
    report_dir = ART_ROOT / "tools/art/source/keeper_hair_284"
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / ".gdignore").touch()
    (report_dir / "texture-validation.json").write_text(json.dumps(reports, indent=2) + "\n")
    print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    run()
