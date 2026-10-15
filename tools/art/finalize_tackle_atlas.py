#!/usr/bin/env python3
"""Reserve guarded swatches for tiny source details within the same 2048 atlas.

Source named geometry determines colors. This avoids mip bleeding on net cord,
rod tips and leaves without increasing textures, surfaces or geometry.
"""
from pathlib import Path
import json, struct, math
from PIL import Image, ImageDraw
from verify_chef_sign import load_glb, accessor
ROOT=Path(__file__).resolve().parents[2]
KIT=ROOT/'assets/rooms/tackle_shop';OUT=ROOT/'output/tackle-214'

def main():
    source=json.loads((OUT/'source-detail-colors.json').read_text())
    colors=sorted({tuple(rgb) for row in source.values() for group in row['vertices'].values() for rgb in group})
    assert len(colors)<=64
    atlas=Image.open(KIT/'room_albedo_ao.png').convert('RGB')
    result=Image.new('RGB',(2048,2048),(120,96,76))
    result.paste(atlas.resize((2048,1920),Image.Resampling.LANCZOS),(0,0))
    draw=ImageDraw.Draw(result);swatches={}
    for i,color in enumerate(colors):
        x=(i%32)*64;y=1920+(i//32)*64
        draw.rectangle((x,y,x+63,y+63),fill=color)
        swatches[color]=((x+32)/2048,(y+32)/2048)
    patched={}
    report={'atlas_size':[2048,2048],'baked_region':[2048,1920],'swatch_tile_px':64,
            'swatches':[{'rgb8':list(c),'gltf_uv':list(uv)} for c,uv in swatches.items()],'modules':{}}
    for path in sorted(KIT.glob('*.glb')):
        doc,original=load_glb(path);data=bytearray(original)
        prim=doc['meshes'][0]['primitives'][0]
        uv_id=prim['attributes']['TEXCOORD_0'];coords=accessor(doc,data,uv_id)
        positions=accessor(doc,data,prim['attributes']['POSITION'])
        normals=accessor(doc,data,prim['attributes']['NORMAL'])
        old_indices=[r[0] for r in accessor(doc,data,prim['indices'])]
        row=source.get(path.stem,{})
        lookup={key.replace('-0.0000','0.0000'):value for key,value in row.get('vertices',{}).items()};mapped=0
        candidates=[(tuple(map(float,key.split(','))),color) for key,color in lookup.items()]
        vertex_colors=[]
        for i,(q,uv) in enumerate(zip(positions,coords)):
            key=','.join(f'{value:.4f}' for value in q).replace('-0.0000','0.0000')
            # glTF normalizes -0.0; the source key can retain its sign.
            if key not in lookup:key=key.replace('-0.0000','0.0000')
            choices=lookup.get(key)
            if choices is None and candidates:
                distance,nearest=min((math.dist(q,point),rgb) for point,rgb in candidates)
                if distance<.00012:choices=nearest
            vertex_colors.append({tuple(c) for c in choices} if choices else set())
            if choices:mapped+=1
        if row.get('complete'):assert mapped==len(coords),(path.name,mapped,len(coords))
        # Coincident vertices can belong to two differently colored source parts
        # (e.g. the red and white halves of one float). Resolve each whole
        # triangle from the intersection of its source-color candidates, and
        # split UV vertices if necessary. Never interpolate between palette tiles.
        new_positions=[];new_normals=[];new_uvs=[];new_indices=[];reuse={};swatch_triangles=0
        for start in range(0,len(old_indices),3):
            ids=old_indices[start:start+3]
            common=vertex_colors[ids[0]] & vertex_colors[ids[1]] & vertex_colors[ids[2]]
            if row.get('complete'):assert common,(path.name,'Missing triangle source color',start//3)
            color=sorted(common)[0] if common else None
            if color is not None:swatch_triangles+=1
            for vi in ids:
                key=(vi,color)
                if key not in reuse:
                    reuse[key]=len(new_positions);new_positions.append(positions[vi]);new_normals.append(normals[vi])
                    new_uvs.append(swatches[color] if color is not None else (coords[vi][0],coords[vi][1]*1920/2048))
                new_indices.append(reuse[key])
        report['modules'][path.stem]={'vertices':len(new_positions),'guarded_source_vertices':mapped,'guarded_triangles':swatch_triangles}
        data=bytearray();views=[];accessors=[]
        for values,fmt,kind,component,target in [(new_positions,'3f','VEC3',5126,34962),(new_normals,'3f','VEC3',5126,34962),
                (new_uvs,'2f','VEC2',5126,34962),([(i,) for i in new_indices],'I','SCALAR',5125,34963)]:
            while len(data)%4:data.append(0)
            offset=len(data)
            for value in values:data.extend(struct.pack('<'+fmt,*value))
            views.append({'buffer':0,'byteOffset':offset,'byteLength':len(data)-offset,'target':target})
            a={'bufferView':len(views)-1,'componentType':component,'count':len(values),'type':kind}
            if len(views)==1:a.update(min=[min(v[j] for v in values) for j in range(3)],max=[max(v[j] for v in values) for j in range(3)])
            accessors.append(a)
        prim['attributes']={'POSITION':0,'NORMAL':1,'TEXCOORD_0':2};prim['indices']=3
        doc['bufferViews']=views;doc['accessors']=accessors;doc['buffers']=[{'byteLength':len(data)}]
        encoded=json.dumps(doc,separators=(',',':')).encode()
        encoded+=b' '*((-len(encoded))%4);data+=b'\0'*((-len(data))%4)
        patched[path]=struct.pack('<4sII',b'glTF',2,12+8+len(encoded)+8+len(data))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(data),b'BIN\0')+data
    result.save(KIT/'room_albedo_ao.png')
    for path,data in patched.items():path.write_bytes(data)
    stats=json.loads((KIT/'asset_stats.json').read_text())
    for row in stats['assets']:row['bytes']=(KIT/(row['name']+'.glb')).stat().st_size
    stats['glb_bytes']=sum(row['bytes'] for row in stats['assets']);stats['atlas_bytes']=(KIT/'room_albedo_ao.png').stat().st_size
    stats['atlas']['guarded_detail_swatches']=len(colors)
    (KIT/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
    (OUT/'atlas-detail-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('GUARDED_DETAIL_SWATCHES',len(colors),flush=True)

if __name__=='__main__':main()
