#!/usr/bin/env python3
"""Pack retained source cloth/hair above a small original linen palette strip."""
import argparse
from pathlib import Path
import numpy as np
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('--runtime-root', type=Path, required=True)
args = parser.parse_args()
source = args.runtime_root / 'assets/avatar/source'
for base, target, fbx, before, after in [
    ('hairhat41_npc_auburn', 'hairhat41_npc_nadia_baker', 'SM_hairHat41.fbx', 'T_auburn_hairHat41_D.png', 'T_nadia_baker_hairHat41_D.png'),
    ('cloth1_1', 'cloth1_1_npc_nadia', 'SK_dt_skin01.fbx', 'T_skin01_1_cloth_D 1.png', 'T_nadia_apron_cloth01_D.png'),
]:
    dest = source / target
    dest.mkdir(parents=True, exist_ok=True)
    original = Image.open(source / base / before).convert('RGBA')
    pixels = np.array(original)
    if base == 'cloth1_1':
        rgb = pixels[..., :3].astype(float)
        red, green, blue = rgb.transpose(2, 0, 1)
        blend = np.clip((blue - red) / 56, 0, 1)
        mask = blue - red > 3
        warm = np.array([201, 153, 140])
        shifted = rgb + (warm - np.array([149, 177, 205])) * blend[..., None]
        pixels[..., :3][mask] = np.clip(np.rint(shifted[mask]), 0, 255).astype(np.uint8)
    packed = Image.new('RGBA', (1024, 1024), '#f0e9dc')
    packed.paste(Image.fromarray(pixels).resize((1024, 896), Image.Resampling.LANCZOS), (0, 0))
    # Sixteen broad constant tiles are safe through the inherited 512px runtime mip chain.
    palette = ['F2EFE5', 'E5E0D3', 'F9F6EC', 'D5CCB9', 'E9DECB', 'F5EAD8', 'CDBF9F', 'FFFFFF'] * 2
    atlas = np.array(packed)
    for i, color in enumerate(palette):
        atlas[896:1024, i * 64:(i + 1) * 64, :3] = [int(color[j:j + 2], 16) for j in (0, 2, 4)]
    Image.fromarray(atlas).save(dest / after)
    for old_name, new_name in [(fbx, fbx), (before, after)]:
        sidecar = dest / (new_name + '.import')
        if not sidecar.exists():
            params = (source / base / (old_name + '.import')).read_text().split('[params]\n', 1)[1]
            importer, kind = ('scene', 'PackedScene') if new_name.endswith('.fbx') else ('texture', 'CompressedTexture2D')
            sidecar.write_text(f'[remap]\nimporter="{importer}"\ntype="{kind}"\n\n[params]\n' + params)
    print('NADIA_TEXTURE', target)
