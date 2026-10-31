"""Combine the room bake and unchanged shared-plant detail in one external atlas."""
from pathlib import Path
import hashlib
import json
import struct
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent
KIT=ROOT/'assets/rooms/tea_house'
OUT=ROOT/'output/tea-216'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor


def save_json(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')


def write_glb(path,doc,blob):
    data=json.dumps(doc,separators=(',',':')).encode();data+=b' '*((-len(data))%4)
    blob=bytes(blob);blob+=b'\0'*((-len(blob))%4)
    path.write_bytes(struct.pack('<III',0x46546C67,2,28+len(data)+len(blob))+
                     struct.pack('<II',len(data),0x4E4F534A)+data+struct.pack('<II',len(blob),0x004E4942)+blob)


def remap(doc,blob,scale,offset):
    seen=set()
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            index=primitive['attributes']['TEXCOORD_0']
            if index in seen:continue
            seen.add(index);a=doc['accessors'][index];view=doc['bufferViews'][a['bufferView']]
            assert a['componentType']==5126 and a['type']=='VEC2'
            uv=np.ndarray((a['count'],2),dtype='<f4',buffer=blob,
                offset=view.get('byteOffset',0)+a.get('byteOffset',0),strides=(view.get('byteStride',8),4))
            uv[:]=uv*np.array(scale)+np.array(offset)
            if 'min' in a:a['min']=uv.min(0).astype(float).tolist()
            if 'max' in a:a['max']=uv.max(0).astype(float).tolist()


def main():
    layout=json.loads((KIT/'layout.json').read_text())
    first,_=load_glb(KIT/'room_shell.glb')
    if first.get('asset',{}).get('extras',{}).get('tea_atlas_layout'):
        print('TEA_ATLAS_ALREADY_FINALIZED');return
    image=Image.open(KIT/'room_albedo_ao.png').convert('RGBA')
    image.save(OUT/'room_bake.png')
    atlas=Image.new('RGBA',(2048,2048),(238,231,216,255))
    atlas.paste(image.resize((1536,2048),Image.Resampling.LANCZOS),(0,0))
    plant_atlas=ROOT/'assets/rooms/_shared/plants/room_albedo_ao.png'
    plants=Image.open(plant_atlas).convert('RGBA').resize((512,512),Image.Resampling.LANCZOS)
    atlas.paste(plants,(1536,1536));atlas.save(KIT/'room_albedo_ao.png')
    stats=[]
    for spec in layout['assets']:
        name=spec['name'];source=ROOT/'assets/rooms/_shared/plants'/f'{spec["source"]}.glb' if 'source' in spec else KIT/spec['file']
        doc,data=load_glb(source);blob=bytearray(data)
        remap(doc,blob,[.25,.25],[.75,.75]) if 'source' in spec else remap(doc,blob,[.75,1.],[0,0])
        doc['images']=[{'uri':'room_albedo_ao.png'}];doc['textures']=[{'source':0,'sampler':0}]
        doc['samplers']=[{'magFilter':9729,'minFilter':9987,'wrapS':33071,'wrapT':33071}]
        material={'name':'TeaHouse_'+spec['material'],'pbrMetallicRoughness':{'baseColorFactor':[1,1,1,1],
            'baseColorTexture':{'index':0},'metallicFactor':0.,'roughnessFactor':.85}}
        if spec['material']=='foliage':material.update({'alphaMode':'MASK','alphaCutoff':.45,'doubleSided':True})
        if spec['material']=='glow':material.update({'emissiveFactor':[1.,.73,.38],'emissiveTexture':{'index':0}})
        doc['materials']=[material]
        vertices=[];triangles=0;surfaces=0
        for mesh in doc['meshes']:
            mesh['name']=name+'_mobile'
            for primitive in mesh['primitives']:
                primitive['material']=0;surfaces+=1
                vertices.extend(accessor(doc,blob,primitive['attributes']['POSITION']))
                triangles+=len(accessor(doc,blob,primitive['indices']))//3
        doc['asset'].setdefault('extras',{})['tea_atlas_layout']='room-left-1536; shared-plants-bottom-right-512'
        path=KIT/spec['file'];write_glb(path,doc,blob)
        points=np.array(vertices)
        stats.append({'name':name,'file':spec['file'],'triangles':triangles,'surfaces':surfaces,
            'bounds':[points.min(0).tolist(),points.max(0).tolist()],'dimensions_m':np.ptp(points,axis=0).tolist(),
            'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    names={a['name']:a for a in stats}
    placed=[a['name'] for a in layout['assets'] if not a['review_only']]+[a['asset'] for a in layout['instances']]
    vegetation={a['name'] for a in layout['assets'] if a['vegetation']}
    report={'assets':stats,'scene_triangles':sum(names[name]['triangles'] for name in placed),
        'static_draw_surfaces':sum(names[name]['surfaces'] for name in placed),
        'plant_triangles':sum(names[name]['triangles'] for name in placed if name in vegetation),
        'atlas':{'size':[2048,2048],'file':'room_albedo_ao.png','room_pixels':[0,0,1536,2048],
            'shared_plant_pixels':[1536,1536,512,512],'preserve_plant_alpha_scissor':True,
            'shared_plant_atlas_sha256':hashlib.sha256(plant_atlas.read_bytes()).hexdigest()},
        'limits':{'triangles':200000,'plant_triangles':100000,'surfaces':60}}
    assert report['scene_triangles']<=200000 and report['plant_triangles']<=100000 and report['static_draw_surfaces']<=60
    save_json(KIT/'asset_stats.json',report)
    print(json.dumps({k:v for k,v in report.items() if k!='assets'},indent=2))


if __name__=='__main__':main()
