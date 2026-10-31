"""Read exported GLB buffers, not layout estimates. Requires numpy and Pillow."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
KIT = ROOT/'assets/rooms/poi_city_park'
OUTPUT = ROOT/'output/poi-city-park-320'
CHECKS = []


def check(ok, name):
    CHECKS.append({'check': name, 'passed': bool(ok)})
    print('PASS' if ok else 'FAIL', name)


def glb(path, raw=None):
    raw = path.read_bytes() if raw is None else raw
    check(raw[:4] == b'glTF', f'{path.stem}: GLB header')
    length = struct.unpack_from('<I',raw,12)[0]
    doc = json.loads(raw[20:20+length])
    data = raw[28+length:]
    def accessor(index):
        a = doc['accessors'][index]; v = doc['bufferViews'][a['bufferView']]
        dtype = {5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]
        cols = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        size = np.dtype(dtype).itemsize
        offset = v.get('byteOffset',0)+a.get('byteOffset',0)
        return np.ndarray((a['count'],cols),dtype=dtype,buffer=data,offset=offset,
                          strides=(v.get('byteStride',cols*size),size)).copy()
    all_points=[]; triangles_canonical=[]; tris=0; surfaces=0; zero_area=0; uv_min=1.;uv_max=0.
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            surfaces += 1
            points = accessor(primitive['attributes']['POSITION'])
            all_points.append(points)
            indices = accessor(primitive['indices']).ravel().reshape(-1,3)
            tris += len(indices)
            triangles=points[indices]
            triangles_canonical.extend(tuple(sorted(tuple(v) for v in triangle)) for triangle in np.rint(triangles*1e5).astype(np.int64))
            areas=np.linalg.norm(np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]),axis=1)/2
            zero_area += int(np.sum(areas<1e-12))
            check(np.isfinite(points).all(),f'{path.stem}: finite measured positions')
            if 'TEXCOORD_0' in primitive['attributes']:
                uv=accessor(primitive['attributes']['TEXCOORD_0'])
                uv_min=min(uv_min,float(uv.min()));uv_max=max(uv_max,float(uv.max()))
                check(np.isfinite(uv).all() and uv_min>=-.0001 and uv_max<=1.0001,f'{path.stem}: atlas UVs in unit square')
    points=np.concatenate(all_points)
    return {'file':str(path.relative_to(ROOT)),'triangles':tris,'surfaces':surfaces,
            'bounds':[points.min(axis=0).astype(float).tolist(),points.max(axis=0).astype(float).tolist()],
            'dimensions_m':np.ptp(points,axis=0).astype(float).tolist(),'degenerate_triangles':zero_area,
            'mesh_names':[m['name'] for m in doc['meshes']], 'has_images':bool(doc.get('images')),
            'geometry_signature_10um':hashlib.sha256(np.array(sorted(triangles_canonical),dtype='<i8').tobytes()).hexdigest(),
            'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}


def main():
    layout=json.loads((KIT/'layout.json').read_text())
    stats=json.loads((KIT/'asset_stats.json').read_text())
    measured={}
    for asset in layout['assets']:
        path=(KIT/asset['file']).resolve()
        info=glb(path)
        measured[asset['name']]=info
        check(info['surfaces']==1,asset['name']+': one surface')
        check(info['mesh_names']==[asset['name']+'_mobile'],asset['name']+': named mobile mesh')
        check(not info['has_images'],asset['name']+': no duplicated embedded atlas')
        check((ROOT/asset['provenance']).is_file(),asset['name']+': provenance exists')
        check('gltf/texture_map_mode=1' in Path(str(path)+'.import').read_text(),asset['name']+': texture_map_mode=1')
        check(info['degenerate_triangles']==0,asset['name']+': no zero-area triangles')
    placed=[a['name'] for a in layout['assets'] if not a['review_only']]+[a['asset'] for a in layout['instances']]
    tris=sum(measured[n]['triangles'] for n in placed)
    surfaces=sum(measured[n]['surfaces'] for n in placed)
    plant_names={a['name'] for a in layout['assets'] if a['vegetation']}
    plant_tris=sum(measured[n]['triangles'] for n in placed if n in plant_names)
    check(tris==stats['scene_triangles'] and tris<=150000,'Measured placed triangles <=150000 and match manifest')
    check(surfaces==stats['static_draw_surfaces'] and surfaces<=50,'Measured placed surfaces <=50 and match manifest')
    check(plant_tris==stats['plant_triangles'] and plant_tris<=100000,'Measured vegetation <=100000 and matches manifest')
    check(Image.open(KIT/'room_albedo_ao.png').size==(2048,2048),'Atlas actual dimensions 2048x2048')
    check(abs(measured['park_ground']['dimensions_m'][0]-8)<.0001 and abs(measured['park_ground']['dimensions_m'][2]-8)<.0001,'Measured 8x8m ground')
    check(abs(measured['green_bench']['dimensions_m'][0]-1.40)<.0001,'Measured green bench width 1.40m')
    check(abs(measured['green_bench']['dimensions_m'][1]-.95)<.0001,'Measured green bench top .95m')
    check(measured['front_shrub']['bounds'][1][1]<=1.0,'Entrance shrubs below 1.0m')
    check(abs(measured['white_bench']['dimensions_m'][0]-1.04)<.0001,'Measured decorative white bench width 1.04m')
    source_fountain=glb(ROOT/'assets/farm/art/deco_fountain.glb')
    check(np.allclose(measured['fountain']['bounds'],source_fountain['bounds'],atol=2e-6),'Fountain bounds match real unscaled farm asset')
    check(abs(measured['birdbath']['dimensions_m'][1]-.84)<.0001,'Measured birdbath height .84m')
    check(abs(measured['park_lamp']['dimensions_m'][1]-2.20)<.0001,'Measured lamp height 2.20m')
    span=measured['parterre_hedge']['dimensions_m']
    check(all(1.5<=span[i]<=2.15 for i in [0,2]),'Measured three-lobed parterre is approximately 1.5-2m per side')
    for name in ['parterre_hedge','parterre_flowers','fountain','park_tree']:
        path=ROOT/measured[name]['file']
        raw=subprocess.check_output(['git','show','f40ee359:'+str(path.relative_to(ROOT))],cwd=ROOT)
        old=glb(path,raw)
        check(measured[name]['geometry_signature_10um']==old['geometry_signature_10um'],name+': accepted v1 geometry preserved to 10 micrometres')
    for entry in stats['assets']:
        entry.update(measured[entry['name']])
    (KIT/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
    result={'checks':CHECKS,'passed':all(c['passed'] for c in CHECKS),'assets':measured,
            'placed_triangles':tris,'placed_surfaces':surfaces,'plant_triangles':plant_tris,
            'note':'Bounds read from raw exported position buffers; local GLB roots have unit transforms.'}
    OUTPUT.mkdir(parents=True,exist_ok=True)
    (OUTPUT/'geometry-validation.json').write_text(json.dumps(result,indent=2)+'\n')
    if not result['passed']:sys.exit(1)


if __name__=='__main__':main()
