#!/usr/bin/env python3
"""Independent exported GLB audit. No Blender/Godot or third-party dependencies.

Checks packed topology, colors, normals, shared geometry, physical bounds and
the post-only collision contract. Exits nonzero on failure.
"""
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import struct

ROOT=Path(__file__).resolve().parents[2]
IDS=['chef_sign_a','chef_sign_b']


def load_glb(path):
    data=path.read_bytes()
    assert data[:4]==b'glTF'
    n=struct.unpack_from('<I',data,12)[0]
    doc=json.loads(data[20:20+n])
    return doc,data[28+n:]


def accessor(doc,data,index):
    a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
    sizes={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}
    types={5121:'B',5123:'H',5125:'I',5126:'f'}
    fmt='<'+types[a['componentType']]*sizes[a['type']]
    stride=v.get('byteStride',struct.calcsize(fmt))
    start=v.get('byteOffset',0)+a.get('byteOffset',0)
    values=[struct.unpack_from(fmt,data,start+i*stride) for i in range(a['count'])]
    if a.get('normalized'):
        divisor={5121:255,5123:65535}[a['componentType']]
        values=[tuple(x/divisor for x in row) for row in values]
    return values


def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def sub(a,b): return tuple(x-y for x,y in zip(a,b))


def main():
    manifest=json.loads((ROOT/'assets/farm/art/manifest.json').read_text())['assets']
    result={'assets':[], 'checks':[]}
    def check(ok,label):
        result['checks'].append({'check':label,'passed':bool(ok)})
        if not ok: print('FAIL',label)
    shared=[]
    for id in IDS:
        path=ROOT/'assets/farm/art'/f'{id}.glb'
        doc,data=load_glb(path)
        entry=manifest[id]
        check(len(doc.get('meshes',[]))==1,id+': exactly one mesh')
        prim=doc['meshes'][0]['primitives']
        check(len(prim)==1,id+': exactly one primitive / surface')
        check(len(doc.get('materials',[]))==1 and not doc.get('images') and not doc.get('textures'),id+': one material and no textures')
        p=prim[0]
        check(set(p['attributes'])=={'POSITION','NORMAL','COLOR_0'},id+': positions / normals / colors only')
        positions=accessor(doc,data,p['attributes']['POSITION'])
        normals=accessor(doc,data,p['attributes']['NORMAL'])
        colors=accessor(doc,data,p['attributes']['COLOR_0'])
        indices=[v[0] for v in accessor(doc,data,p['indices'])]
        triangles=[indices[i:i+3] for i in range(0,len(indices),3)]
        check(len(triangles)==entry['triangles'] and len(triangles)<=1500,id+': triangles / budget')
        check(all(len(c)==3 or (len(c)==4 and abs(c[3]-1)<1e-6) for c in colors),id+': opaque vertex color (VEC3 defaults alpha to 1)')
        bounds=[[min(v[i] for v in positions) for i in range(3)],
                [max(v[i] for v in positions) for i in range(3)]]
        check(all(abs(bounds[j][i]-entry['bounds'][j][i])<1e-6 for i in range(3) for j in range(2)),id+': measured GLB bounds match manifest')
        check(abs(bounds[0][1])<1e-6 and 1.6<=bounds[1][1]<=1.8,id+': grounded and height in range')
        nodes=doc['nodes']
        check(all(n.get('scale',[1,1,1])==[1,1,1] for n in nodes),id+': no negative / non-unit scale')
        marker=next((n for n in nodes if n.get('name')=='board_center'),{})
        check(marker.get('translation')==entry['board_center'] or all(abs(x-y)<1e-6 for x,y in zip(marker.get('translation',[]),entry['board_center'])) and len(marker.get('translation',[]))==3,id+': exact board_center empty')
        collider=entry['collider']
        check(collider['at']==[0,.87,0] and collider['size']==[.28,1.74,.28],id+': post-only collider')
        check(entry['footprint']==.65 and entry['board_bottom']>=1,id+': single anchor cell / board bottom')
        signature=Counter()
        bad_normals=0
        degenerate=0
        for tri in triangles:
            a,b,c=[positions[i] for i in tri]
            normal=cross(sub(b,a),sub(c,a))
            area=math.sqrt(sum(x*x for x in normal))
            if area<1e-10: degenerate+=1
            average=[sum(normals[i][j] for i in tri) for j in range(3)]
            if sum(x*y for x,y in zip(normal,average))< -1e-9: bad_normals+=1
            if max(a[1],b[1],c[1])>.20001:
                signature[tuple(sorted(tuple(round(x,5) for x in positions[i]+normals[i]+colors[i]) for i in tri))]+=1
        check(degenerate==0,id+': no zero-area triangles')
        check(bad_normals==0,id+': reflected winding agrees with normals')
        shared.append(signature)
        result['assets'].append({'id':id,'triangles':len(triangles),'bounds':bounds,
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,
            'shared_non_foot_triangles':sum(signature.values())})
    check(shared[0]==shared[1],'A/B: all non-foot triangles / normals / colors identical (10 micrometre precision)')
    result['failures']=[c for c in result['checks'] if not c['passed']]
    out=ROOT/'output/chef-sign-282/glb-validation.json'
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2)+'\n')
    print(f"GLB audit: {len(result['checks'])} checks, {len(result['failures'])} failures")
    raise SystemExit(bool(result['failures']))


if __name__=='__main__': main()
