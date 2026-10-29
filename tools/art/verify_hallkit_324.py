#!/usr/bin/env python3
"""Read exported triangles independently: scale, palette, source hashes, seats, panes."""
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image

from verify_chef_sign import load_glb, accessor

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT/'assets/rooms/_shared/shell_hall'
OUTPUT = ROOT/'output/hallkit-324'
report = {'checks': [], 'assets': {}, 'method': 'Decoded GLB vertex/index arrays; independent ray/triangle seat and canopy probes.'}


def check(ok, name):
    report['checks'].append({'check': name, 'passed': bool(ok)})
    if not ok: print('FAIL', name)


def ray(triangles, origin, direction):
    origin, direction = np.array(origin), np.array(direction)
    a, b, c = triangles[:, 0], triangles[:, 1], triangles[:, 2]
    edge1, edge2 = b-a, c-a
    p = np.cross(np.broadcast_to(direction, edge2.shape), edge2)
    det = np.sum(edge1*p, axis=1)
    valid = np.abs(det) > 1e-10
    inv = np.divide(1, det, out=np.zeros_like(det), where=valid)
    t = origin-a
    u = np.sum(t*p, axis=1)*inv
    q = np.cross(t, edge1)
    v = q@direction*inv
    distance = np.sum(edge2*q, axis=1)*inv
    hits = distance[valid & (u >= -1e-7) & (v >= -1e-7) & (u+v <= 1+1e-7) & (distance > 1e-6)]
    return None if not len(hits) else float(hits.min())


stats = json.loads((KIT/'asset_stats.json').read_text())
palette = json.loads((KIT/'palette.json').read_text())
image = Image.open(KIT/'hallkit_palette.png')
check(image.size == (2048, 2048), 'one 2048-square atlas')
check(len(list(KIT.glob('*.png'))) == 1, 'no original kit atlases copied')
texture_config = (KIT/'hallkit_palette.png.import').read_text()
check('compress/mode=2' in texture_config and 'mipmaps/generate=true' in texture_config,
      'atlas configured for VRAM compression and mipmaps')
for slot, data in palette['slots'].items():
    rect = data['uv_rect_gltf']
    x, y = int(rect[0]*2048)+10, int(rect[1]*2048)+10
    expected = tuple(int(data['hex_srgb'][i:i+2], 16) for i in [0, 2, 4])
    check(image.getpixel((x, y))[:3] == expected, slot+' exact Basic Room swatch')
for asset in stats['assets']:
    name = asset['name']; doc, blob = load_glb(KIT/asset['file'])
    check(doc['images'] == [{'uri': 'hallkit_palette.png'}], name+' only external shared atlas')
    check('gltf/texture_map_mode=1' in (KIT/(asset['file']+'.import')).read_text(), name+' texture_map_mode=1')
    geometry, all_points = {}, []
    actual_count = 0; surface_count = 0
    for node in doc['nodes']:
        if 'mesh' not in node: continue
        check(not any(key in node for key in ['matrix', 'translation', 'rotation', 'scale']), name+'/'+node['name']+' identity local transform')
        arrays = []
        for prim in doc['meshes'][node['mesh']]['primitives']:
            vertices = np.array(accessor(doc, blob, prim['attributes']['POSITION']))
            normals = np.array(accessor(doc, blob, prim['attributes']['NORMAL']))
            uv = np.array(accessor(doc, blob, prim['attributes']['TEXCOORD_0']))
            indices = np.array(accessor(doc, blob, prim['indices'])).ravel().reshape(-1, 3)
            triangles = vertices[indices]; arrays.append(triangles); all_points.extend(vertices)
            actual_count += len(triangles); surface_count += 1
            check(np.isfinite(vertices).all() and np.isfinite(uv).all(), name+'/'+node['name']+' finite vertices and UVs')
            normal = np.cross(triangles[:, 1]-triangles[:, 0], triangles[:, 2]-triangles[:, 0])
            check((np.linalg.norm(normal, axis=1) > 1e-10).all(), name+'/'+node['name']+' no zero-area triangles')
            check((np.sum(normal*normals[indices].mean(1), axis=1) >= -1e-7).all(), name+'/'+node['name']+' winding agrees with shading normals')
            # Every complete triangle stays within one padded palette tile.
            ok = True
            for tri_uv in uv[indices]:
                ok &= any(np.all(tri_uv[:, 0] >= slot['uv_rect_gltf'][0]-1e-6)
                          and np.all(tri_uv[:, 0] <= slot['uv_rect_gltf'][2]+1e-6)
                          and np.all(tri_uv[:, 1] >= slot['uv_rect_gltf'][1]-1e-6)
                          and np.all(tri_uv[:, 1] <= slot['uv_rect_gltf'][3]+1e-6)
                          for slot in palette['slots'].values())
            check(ok, name+'/'+node['name']+' triangles contained in padded swatches')
        geometry[node['name']] = np.concatenate(arrays)
    points = np.array(all_points); lo, hi = points.min(0), points.max(0)
    check(actual_count == asset['triangles'] and actual_count < 8000, name+' actual triangle count and budget')
    check(surface_count == asset['surfaces'], name+' actual surface count')
    check(np.allclose([lo, hi], asset['bounds'], atol=1e-6), name+' actual metre bounds')
    if asset['family'] not in ['sconce', 'frames']:
        check(abs(lo[1]) < 1e-6, name+' floor pivot grounded')
    else:
        check(abs(lo[2]) < 1e-6, name+' wall mounting plane Z=0')
    measured = {'triangles': actual_count, 'surfaces': surface_count,
                'bounds': [lo.tolist(), hi.tolist()], 'seat_probes': []}
    if 'seat_height_m' in asset:
        for anchor, position in asset['anchors'].items():
            distance = ray(geometry['Body'], [position[0], .75, position[2]], [0, -1, 0])
            height = None if distance is None else .75-distance
            check(height is not None and abs(height-.715) < .001, name+'/'+anchor+' actual seat surface 0.715 m')
            measured['seat_probes'].append({'anchor': anchor, 'height_m': height})
    if asset['family'] == 'frames':
        check(len(geometry.get('Artwork', [])) == 2, name+' independent two-triangle picture face')
    if asset['family'] == 'bench':
        check(hi[1] <= .716, name+' no floating seam or stitch above seat')
    if asset['family'] == 'display':
        # Inside the canopy; forward/back, both ends and roof must all be closed.
        origin = [0, 1.35, 0]
        for direction in [[1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1], [0, 1, 0]]:
            check(ray(geometry['Glass'], origin, direction) is not None, name+' closed canopy ray '+str(direction))
        mat = next(m for m in doc['materials'] if m['name'] == 'HallGlass')
        check(mat['alphaMode'] == 'BLEND' and mat['doubleSided'], name+' transparent two-sided glass')
    provenance = json.loads((KIT/asset['provenance']).read_text())
    for source in provenance['sources'].values():
        check(hashlib.sha256((ROOT/source['glb']).read_bytes()).hexdigest() == source['sha256'], name+' source GLB hash retained: '+source['glb'])
        check(hashlib.sha256((ROOT/source['blend']).read_bytes()).hexdigest() == source['blend_sha256'], name+' named source hash retained: '+source['blend'])
    report['assets'][name] = measured
check(sum(a['triangles'] for a in report['assets'].values()) == stats['unique_triangles'], 'unique triangle total')
check(len({a['family'] for a in stats['assets']}) == 8, 'exactly eight requested prop families')
report['passed'] = all(c['passed'] for c in report['checks'])
report['failures'] = [c['check'] for c in report['checks'] if not c['passed']]
(OUTPUT/'geometry-validation.json').write_text(json.dumps(report, indent=2)+'\n')
print('HALLKIT_GEOMETRY', report['passed'], len(report['checks']), 'checks')
sys.exit(0 if report['passed'] else 1)
