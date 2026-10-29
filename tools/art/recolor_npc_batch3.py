#!/usr/bin/env python3
"""SGODOT-362 texture variants. FBX, hair and protected wardrobe pixels stay exact."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
VARIANTS = [
    ('hairhat51', 'hairhat51_npc_lena', 'SM_hairHat51.fbx', 'T_skin40_hairHat_D.png', 'T_lena_hairHat51_D.png'),
    ('hairhat36_npc_pip', 'hairhat36_npc_rafa', 'SM_hairHat36.fbx', 'T_skin28_hairHat_D.png', 'T_rafa_hairHat36_D.png'),
    ('cloth1_1', 'cloth1_1_npc_rafa', 'SK_dt_skin01.fbx', 'T_skin01_1_cloth_D 1.png', 'T_rafa_cloth01_D.png'),
]


def mask_for(mesh, component_ids, size, pad=0):
    image = Image.new('L', size)
    draw = ImageDraw.Draw(image)
    for t in mesh['triangles']:
        if t['component'] in component_ids:
            draw.polygon([(u * size[0], (1 - v) * size[1]) for u, v in t['uv']], fill=255)
    if pad:
        image = image.filter(ImageFilter.MaxFilter(2 * pad + 1))
    return np.asarray(image) > 0


def remap(rgb, mask, colors):
    values = (rgb @ np.array([.2126, .7152, .0722]))[mask]
    knots = np.percentile(values, [0, 50, 100])
    palette = np.array([[int(c[i:i + 2], 16) for i in (0, 2, 4)] for c in colors])
    out = rgb.copy()
    out[mask] = np.stack([np.interp(values, knots, palette[:, i]) for i in range(3)], axis=-1)
    return out


def surface_height(mesh, size, component):
    width, height = size
    values = np.full((height, width), np.nan)
    vertices = np.array(mesh['vertices'])
    conflicts = []
    for t in mesh['triangles']:
        if t['component'] != component:
            continue
        p = np.array(t['uv']) * [width, -height] + [0, height]
        x0, y0 = np.maximum(np.floor(p.min(axis=0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(p.max(axis=0)).astype(int), [width - 1, height - 1])
        xx, yy = np.meshgrid(np.arange(x0, x1 + 1) + .5, np.arange(y0, y1 + 1) + .5)
        a, b, c = p
        denominator = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(denominator) < 1e-7:
            continue
        wa = ((b[1] - c[1]) * (xx - c[0]) + (c[0] - b[0]) * (yy - c[1])) / denominator
        wb = ((c[1] - a[1]) * (xx - c[0]) + (a[0] - c[0]) * (yy - c[1])) / denominator
        wc = 1 - wa - wb
        inside = (wa >= -1e-6) & (wb >= -1e-6) & (wc >= -1e-6)
        heights = vertices[t['vertices'], 1]
        interpolated = wa * heights[0] + wb * heights[1] + wc * heights[2]
        view = values[y0:y1 + 1, x0:x1 + 1]
        shared = inside & np.isfinite(view)
        if shared.any():
            conflicts.extend(abs(view[shared] - interpolated[shared]).tolist())
        view[inside] = interpolated[inside]
    # Six-pixel gutter extends the same stripe phase into unused island margins.
    for _ in range(6):
        known = np.isfinite(values)
        total = np.zeros_like(values)
        count = np.zeros_like(values)
        for dy, dx in [(0, 1), (0, -1), (1, 0), (-1, 0)]:
            shifted = np.roll(values, (dy, dx), axis=(0, 1))
            valid = np.isfinite(shifted)
            total += np.where(valid, shifted, 0)
            count += valid
        fill = ~known & (count > 0)
        values[fill] = total[fill] / count[fill]
    return values, max(conflicts, default=0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime-root', type=Path, required=True)
    parser.add_argument('--inspection', type=Path, required=True)
    args = parser.parse_args()
    dest_art = ROOT / 'tools/art/source/npc_batch3'
    dest_art.mkdir(parents=True, exist_ok=True)
    (dest_art / '.gdignore').touch()
    reports = []
    for base, part, fbx, png, target in VARIANTS:
        source = args.runtime_root / 'assets/avatar/source' / base
        dest = args.runtime_root / 'assets/avatar/source' / part
        dest.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / fbx, dest / fbx)
        mesh = next(m for m in json.loads((args.inspection / (base + '.json')).read_text())
                    if m['name'] == ('cloth' if base == 'cloth1_1' else 'hairHat'))
        original = np.asarray(Image.open(source / png).convert('RGBA'))
        rgb = original[..., :3].astype(float)
        size = (original.shape[1], original.shape[0])
        r, g, b = rgb.transpose(2, 0, 1)
        detail = {}
        if base == 'hairhat51':
            hair = mask_for(mesh, [0], size)
            badge = mask_for(mesh, [2], size, 6) & (g - b > 30)
            mask = (g - b > 30) & ~hair
            result = remap(rgb, mask & ~badge, ['98702C', 'C9A346', 'E7C76D'])
            result = remap(result, badge, ['202D40', '314762', '4D6682'])
            protected = hair
            detail = {'hat_palette': ['98702C', 'C9A346', 'E7C76D'], 'badge': 'navy',
                      'mask': 'G-B > 30, excluding hair UV coverage; badge component 2'}
        elif base == 'hairhat36_npc_pip':
            protected = mask_for(mesh, [0, 1, 3, 4, 5, 6, 7, 8, 9, 10], size)
            mask = mask_for(mesh, [2], size, 6) & (b - r > 10) & ~protected
            result = remap(rgb, mask, ['B9BDC3', 'E9E8DF', 'F8F5EB'])
            detail = {'crown_palette': ['B9BDC3', 'E9E8DF', 'F8F5EB'],
                      'mask': 'Crown component 2 blue pixels only; all other component UVs excluded'}
        else:
            protected = mask_for(mesh, [1], size, 2)
            heights, overlap = surface_height(mesh, size, 0)
            # Original blue/white shirt family is disjoint from khaki shorts.
            mask = np.isfinite(heights) & (b >= r - 2) & ~protected
            blue_fraction = np.clip((b - r) / 56.0, 0, 1)
            expected_luma = blue_fraction * 172.0 + (1 - blue_fraction) * 232.0
            shade = np.clip((rgb @ [.2126, .7152, .0722]) / expected_luma, .70, 1.06)
            phase = np.nan_to_num(heights) % 6.0
            stripe = np.clip((1.1 - abs(phase - 3.0)) / .15 + .5, 0, 1)
            white = np.array([239, 239, 232])
            navy = np.array([37, 56, 79])
            fabric = (white + (navy - white) * stripe[..., None]) * shade[..., None]
            result = rgb.copy()
            result[mask] = fabric[mask]
            detail = {'pattern': 'Horizontal stripes projected from original FBX rest-space Y into existing UVs',
                      'period_cm': 6.0, 'navy_band_cm': 2.2, 'palette': ['EFEFE8', '25384F'],
                      'max_overlapping_uv_height_difference_cm': overlap}
            assert overlap < .25, 'Shared UVs cannot carry consistent horizontal stripes'
        result = np.clip(np.rint(result), 0, 255).astype(np.uint8)
        rgba = original.copy()
        rgba[..., :3] = result
        assert np.array_equal(rgba[protected], original[protected]), part
        assert np.array_equal(rgba[~mask], original[~mask]), part
        Image.fromarray(rgba).save(dest / target)
        for old_name, new_name in [(fbx, fbx), (png, target)]:
            sidecar = dest / (new_name + '.import')
            if not sidecar.exists():
                params = (source / (old_name + '.import')).read_text().split('[params]\n', 1)[1]
                importer, kind = ('scene', 'PackedScene') if new_name.endswith('.fbx') else ('texture', 'CompressedTexture2D')
                sidecar.write_text(f'[remap]\nimporter="{importer}"\ntype="{kind}"\n\n[params]\n' + params)
        Image.fromarray((mask * 255).astype(np.uint8)).save(dest_art / (part + '_mask.png'))
        reports.append({'id': part, 'base': base, 'triangles': len(mesh['triangles']), 'triangle_delta': 0,
                        'fbx_byte_identical': (source / fbx).read_bytes() == (dest / fbx).read_bytes(),
                        'source_texture_size': size, 'changed_pixels': int(np.any(rgba != original, axis=2).sum()),
                        'protected_pixels_exact': True, 'outside_mask_exact': True, 'alpha_exact': True,
                        'sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [dest / fbx, dest / target]},
                        **detail})
    (dest_art / 'texture-validation.json').write_text(json.dumps(reports, indent=2) + '\n')
    print(json.dumps(reports, indent=2))


if __name__ == '__main__':
    main()
