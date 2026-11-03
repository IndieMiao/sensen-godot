"""Update only quartz RGB bytes in the approved v1 GLB and audit the result."""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import sys
import numpy as np
from quartz_colour import facet_colours

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4];OUT=ROOT/'output/mine-vein-355'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
parser=argparse.ArgumentParser();parser.add_argument('--baseline',type=Path,required=True);args=parser.parse_args()
path=ROOT/'output/monsters-355/runtime/assets/mine/types/vein/backdrop.glb'
before=args.baseline.read_bytes();current=path.read_bytes();doc,data=load_glb(args.baseline)
primitive=doc['meshes'][0]['primitives'][0];attributes=primitive['attributes']
colours=np.array(accessor(doc,data,attributes['COLOR_0']))
uv=np.array(accessor(doc,data,attributes['TEXCOORD_1']))
indices=np.array(accessor(doc,data,primitive['indices'])).reshape(-1,3)
normals=np.array(accessor(doc,data,attributes['NORMAL']))
quartz=(uv[:,1]>.99)&(colours[:,2]>colours[:,0])&(colours[:,:3].min(axis=1)>.2)
triangles=indices[np.all(quartz[indices],axis=1)]
assert len(np.unique(triangles))==triangles.size
new_colours=facet_colours(normals[triangles].mean(axis=1).tolist())
acc=doc['accessors'][attributes['COLOR_0']];view=doc['bufferViews'][acc['bufferView']]
assert acc['componentType']==5123 and acc['normalized'] and acc['type']=='VEC4'
binary_start=28+struct.unpack_from('<I',before,12)[0]
offset=binary_start+view.get('byteOffset',0)+acc.get('byteOffset',0);stride=view.get('byteStride',8)
allowed=np.zeros(len(before),dtype=bool)
for vertex in np.flatnonzero(quartz):allowed[offset+int(vertex)*stride:offset+int(vertex)*stride+6]=True
assert len(current)==len(before)
assert np.array_equal(np.frombuffer(current,dtype=np.uint8)[~allowed],np.frombuffer(before,dtype=np.uint8)[~allowed]),'Non-quartz data changed; refusing to overwrite'
result=bytearray(current)
for triangle,color in zip(triangles,new_colours):
    for vertex in triangle:struct.pack_into('<3H',result,offset+int(vertex)*stride,*(round(value*65535) for value in color))
path.write_bytes(result)
after,new_data=load_glb(path)
assert after==doc
for name,index in attributes.items():
    if name!='COLOR_0':assert accessor(doc,data,index)==accessor(after,new_data,index),name
assert accessor(doc,data,primitive['indices'])==accessor(after,new_data,primitive['indices'])
decoded=np.array(accessor(after,new_data,attributes['COLOR_0']))
assert np.array_equal(decoded[~quartz],colours[~quartz])
assert np.array_equal(decoded[:,3],colours[:,3])
srgb=np.where(decoded[quartz,:3]<=.0031308,decoded[quartz,:3]*12.92,1.055*decoded[quartz,:3]**(1/2.4)-.055)
lightness=srgb@np.array([.2126,.7152,.0722])
assert .54<lightness.min()<.56 and .64<lightness.max()<.66 and .09<np.ptp(lightness)<.11
report={'passed':True,'baseline_sha256':hashlib.sha256(before).hexdigest(),'sha256':hashlib.sha256(result).hexdigest(),
    'changed_rgb_vertices':int(quartz.sum()),'changed_bytes':int((np.frombuffer(before,dtype=np.uint8)!=np.frombuffer(result,dtype=np.uint8)).sum()),
    'quartz_triangles':len(triangles),'srgb_rgb_min':srgb.min(axis=0).tolist(),'srgb_rgb_max':srgb.max(axis=0).tolist(),
    'srgb_luma_min':float(lightness.min()),'srgb_luma_max':float(lightness.max()),'srgb_luma_span':float(np.ptp(lightness)),
    'unchanged':['JSON and all material settings','indices','POSITION','NORMAL','TEXCOORD_0','TEXCOORD_1','all alpha','all rust and grayscale colours'],
    'method':'Only the existing COLOR_0 RGB ushort components on the 501 approved quartz vertices are patched.'}
(OUT/'quartz-colour-validation.json').write_text(json.dumps(report,indent=2)+'\n')
provenance=json.loads((SRC/'reuse_provenance.json').read_text());provenance['stage']='v1.2';provenance['runtime_sha256']=report['sha256']
provenance['changes']=[note for note in provenance['changes'] if 'quartz linear peak' not in note and not note.startswith(('v1.1:','v1.2:'))]
provenance['changes'].append('v1.2: quartz RGB reduced to pale lavender sRGB luma .55-.65 with existing facet shading; rust, shape, position, UV and UID retained. Only F21-40 ground palette entries brighten to cool blue for ore separation.')
(SRC/'reuse_provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,indent=2))
