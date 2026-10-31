"""Independent checks from the final GLB buffers and approved metre dimensions."""
import hashlib
import json
import struct
import sys
import numpy as np
from PIL import Image
from dependencies import ROOT,SRC,OUT,DEPS,HALL,glb_measure,write_json

KIT=ROOT/'assets/rooms/poi_service_hall'
CHECKS=[]


def check(ok,label):
    CHECKS.append({'check':label,'passed':bool(ok)})
    print('PASS' if ok else 'FAIL',label)


def main():
    manifest=json.loads((KIT/'prop_manifest.json').read_text())
    palette=json.loads((KIT/'prop_palette.json').read_text())
    measurements={}
    for spec in manifest['assets']:
        path=KIT/spec['file'];name=spec['name'];info=glb_measure(path);measurements[name]=info
        raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+length]);blob=raw[28+length:]
        def read(index):
            a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
            dtype={5121:'u1',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]
            cols={'SCALAR':1,'VEC2':2,'VEC3':3}[a['type']];size=np.dtype(dtype).itemsize
            return np.ndarray((a['count'],cols),dtype=dtype,buffer=blob,
                offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',cols*size),size))
        check(info['surfaces']==1,name+': one surface')
        check(info['mesh_names']==[name+'_mobile'],name+': named mobile mesh')
        check(info['triangles']==spec['triangles'] and info['triangles']<=8000,name+': measured triangle count and <=8k')
        check(not doc.get('images'),name+': no embedded atlas duplication')
        for primitive in doc['meshes'][0]['primitives']:
            positions=read(primitive['attributes']['POSITION']);indices=read(primitive['indices']).reshape(-1,3)
            triangles=positions[indices]
            areas=np.linalg.norm(np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]),axis=1)/2
            check(np.all(areas>1e-12),name+': no degenerate triangles')
            uv=read(primitive['attributes']['TEXCOORD_0']);valid=np.zeros(len(uv),dtype=bool)
            for slot in palette['slots'].values():
                if slot['kind']!='solid_reuse_swatch':continue
                x0,y0,x1,y1=slot['uv_rect_gltf'];valid|=(uv[:,0]>=x0)&(uv[:,0]<=x1)&(uv[:,1]>=y0)&(uv[:,1]<=y1)
            check(valid.all(),name+': all UVs within shared hall swatch safety margins')
        check((ROOT/spec['provenance']).exists(),name+': provenance exists')
        spec['measured']=info
    dim=lambda name:np.array(measurements[name]['dimensions_m'])
    check(np.allclose(dim('sculpture_base'),[1.86,.40,1.86],atol=.001),'Measured planted base diameter 1.86m and height .40m')
    body=dim('sculpture_body')
    check(body[0]<=.601 and abs(body[1]-1.20)<.001,'Sculpture body <=.60m wide; total sculpture height 1.60m')
    for name in ['display_niche_1','display_niche_2']:
        check(np.allclose(dim(name),[1.10,2.40,.35],atol=.015),name+': approved applied niche envelope')
    check(np.allclose(dim('brochure_rack'),[.71,1.10,.48],atol=.01),'Brochure rack .71 x 1.10 x .48m')
    check(np.allclose(dim('water_dispenser'),[.44,1.30,.54],atol=.001),'Water dispenser .44 x 1.30 x .54m')
    for name,size in [('call_screen',[.80,.50]),('notice_board',[.70,.90]),('name_plaque',[1.0,.35])]:
        check(np.allclose(dim(name)[:2],size,atol=.001),name+': approved board width and height')
    check(abs(dim('window_flowerbox')[0]-1)<.001 and dim('window_flowerbox')[1]<=.201
          and abs(dim('window_flowerbox')[2]-.22)<.001,'Window flowerbox within 1.00 x .20 x .22m')
    check(Image.open(KIT/'hall_albedo_ao_n2.png').size==(2048,2048),'One same-layout 2048x2048 prop atlas')
    check(hashlib.sha256((DEPS/HALL/'hall_albedo_ao.png').read_bytes()).hexdigest()==palette['source_atlas_sha256'],
          'Pinned hall source atlas unchanged')
    triangles=sum(measurements[s['name']]['triangles']*s['quantity'] for s in manifest['assets'])
    surfaces=sum(s['quantity'] for s in manifest['assets'])
    check(triangles<35000 and surfaces==11,'Independent props including two flowerboxes fit reserved budget')
    write_json(KIT/'prop_manifest.json',manifest)
    result={'passed':all(c['passed'] for c in CHECKS),'checks':CHECKS,'assets':measurements,
            'placed_prop_triangles':triangles,'placed_prop_surfaces':surfaces,
            'note':'Independent props only. Final room budget and navigation will be checked after B approval.'}
    write_json(OUT/'details-geometry-validation.json',result)
    if not result['passed']:sys.exit(1)


if __name__=='__main__':main()
