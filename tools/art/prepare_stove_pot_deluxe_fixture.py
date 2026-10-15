#!/usr/bin/env python3
"""Review-only removal of the known Deluxe built-in stove kettle, not room edits.
Exact 1144 triangles / nine components must be confined to the original kettle
bounds and every removed vertex must match Basic kettle translated to its
recorded Deluxe source position within 30 micrometres. Retained attributes,
materials, UVs and source room GLB stay unchanged. Destination must be output/.
"""
import argparse,hashlib,json,struct,sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_chef_sign import load_glb,accessor
ROOT=Path(__file__).resolve().parents[2]

def prepare(destination):
    destination=destination.resolve();assert destination.is_relative_to((ROOT/'output').resolve())
    source=ROOT/'assets/rooms/deluxe_room_10/kitchen_fittings.glb';reference=ROOT/'assets/rooms/basic_room/kettle.glb'
    d,b=load_glb(source);kd,kb=load_glb(reference);assert len(d['meshes'])==1 and len(d['meshes'][0]['primitives'])==1
    p=d['meshes'][0]['primitives'][0];kp=kd['meshes'][0]['primitives'][0]
    v=np.array(accessor(d,b,p['attributes']['POSITION']));kv=np.array(accessor(kd,kb,kp['attributes']['POSITION']))+[-4.08,1.305,-.55]
    ids=np.array(accessor(d,b,p['indices'])).reshape(-1,3);lo=kv.min(0)-.00003;hi=kv.max(0)+.00003
    remove=np.all((v[ids]>=lo)&(v[ids]<=hi),axis=(1,2));removed=ids[remove];kept=ids[~remove]
    nearest=max(np.linalg.norm(kv-point,axis=1).min() for point in np.unique(v[removed].reshape(-1,3),axis=0))
    assert len(removed)==1144 and nearest<.00003,(len(removed),nearest)
    a=d['accessors'][p['indices']];component=a['componentType'];fmt={5121:'B',5123:'H',5125:'I'}[component]
    old_attributes=json.dumps(p['attributes'],sort_keys=True);original_binary=b
    raw=struct.pack('<'+fmt*kept.size,*kept.reshape(-1).tolist());b+=b'\0'*((-len(b))%4);offset=len(b);b+=raw
    d['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(raw),'target':34963});a['bufferView']=len(d['bufferViews'])-1;a['byteOffset']=0;a['count']=int(kept.size);a['min']=[int(kept.min())];a['max']=[int(kept.max())]
    d['buffers'][0]['byteLength']=len(b);payload=json.dumps(d,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4);b+=b'\0'*((-len(b))%4)
    destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(payload)+len(b))+struct.pack('<I4s',len(payload),b'JSON')+payload+struct.pack('<I4s',len(b),b'BIN\0')+b)
    assert b[:len(original_binary)]==original_binary and json.dumps(p['attributes'],sort_keys=True)==old_attributes
    report={'source':str(source.relative_to(ROOT)),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'reference':str(reference.relative_to(ROOT)),'reference_sha256':hashlib.sha256(reference.read_bytes()).hexdigest(),'kettle_source_position':[-4.08,1.305,-.55],'removed_triangles':int(remove.sum()),'retained_triangles':len(kept),'max_vertex_distance_to_original_kettle_m':float(nearest),'all_original_binary_bytes_preserved':True,'source_room_unchanged':True,'output_sha256':hashlib.sha256(destination.read_bytes()).hexdigest()}
    (ROOT/'output/stove-pot-282/deluxe-fixture-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));return destination
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True);args=parser.parse_args();prepare(Path(args.output))
