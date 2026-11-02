"""Approved B assembly: preserved shared shell, room skin and local material variants."""
from pathlib import Path
from collections import deque
import copy
import hashlib
import io
import json
import math
import struct
import subprocess
import sys
import tarfile

import numpy as np
from PIL import Image
from shapely.geometry import Point, box, LineString
from shapely.affinity import rotate, translate
from shapely.ops import unary_union, nearest_points
from dependencies import ROOT, SRC, OUT, DEPS, HALL, glb_measure, write_json, KIT_COMMIT

sys.path.insert(0, str(ROOT/'tools/art'))
from verify_chef_sign import accessor

KIT=ROOT/'assets/rooms/poi_service_hall'
SHELL_COMMIT='8804d7500077c2228846eb0d581c92181f54426c'
AUTHOR='5281cd25-6a49-4df8-9802-f3e534956e80'
BASE='9600c5dcc6035b6e177066985c9c56f32287e892'
PALETTE={}
PROVENANCE={}


def load(path):
    raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0]
    return json.loads(raw[20:20+n]),bytearray(raw[28+n:])


def save_glb(path,doc,blob):
    doc['buffers'][0]['byteLength']=len(blob)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
    blob+=b'\0'*(-len(blob)%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(blob))+
        struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(blob),0x004e4942)+blob)


def replace(doc,blob,index,values):
    a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
    values=np.asarray(values,dtype='<f4');stride=v.get('byteStride',values.shape[1]*4)
    offset=v.get('byteOffset',0)+a.get('byteOffset',0)
    target=np.ndarray(values.shape,dtype='<f4',buffer=blob,offset=offset,strides=(stride,4));target[:]=values
    if 'min' in a:a['min']=values.min(0).astype(float).tolist()
    if 'max' in a:a['max']=values.max(0).astype(float).tolist()


def bind(doc,name,alpha=False):
    doc['images']=[{'uri':'hall_albedo_ao_n2.png'}];doc['textures']=[{'source':0}]
    doc['materials']=[{'name':'N2Plants' if alpha else 'N2HallAtlas',
        'pbrMetallicRoughness':{'baseColorFactor':[1,1,1,1],'baseColorTexture':{'index':0},
            'metallicFactor':0,'roughnessFactor':.85},'doubleSided':alpha,
        'alphaMode':'MASK' if alpha else 'OPAQUE',**({'alphaCutoff':.45} if alpha else {})}]
    for mesh in doc['meshes']:
        mesh['name']=name+'_mobile'
        for primitive in mesh['primitives']:primitive['material']=0


def stage_shell():
    archive=subprocess.check_output(['git','archive',SHELL_COMMIT,HALL,'scenes/shell_hall'],cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:tar.extractall(DEPS,filter='data')
    files=[p for p in (DEPS/HALL).glob('hall_*') if p.is_file()]
    return {str(p.relative_to(DEPS)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}


def swatch_uv(name):
    rect=PALETTE[name]['uv_rect_gltf'];return [(rect[0]+rect[2])/2,(rect[1]+rect[3])/2]


def skin(plant_tiles):
    original=Image.open(DEPS/HALL/'hall_albedo_ao.png').convert('RGBA')
    rgb=np.asarray(original).copy()
    colors={'plaster':'EBCAA8','panel':'D3BEA3','skirting':'C4B098','window':'E7D2B5',
        'plaster_solid':'EBCAA8','wainscot_solid':'D3BEA3','window_solid':'E7D2B5','floor_solid':'DFD1B4',
        'cloth_green':'435B76','print_landscape':'6180A3','print_portrait':'BC4536','sky':'78A8C9'}
    for name,color in colors.items():
        x,y,w,h=PALETTE[name]['rect_px_top_left'];old=np.array(tuple(bytes.fromhex(PALETTE[name]['hex_srgb'])))
        modulation=np.median(rgb[y:y+h,x:x+w,:3].astype(float)/old,axis=2)
        rgb[y:y+h,x:x+w,:3]=np.clip(modulation[:,:,None]*np.array(tuple(bytes.fromhex(color))),0,255).astype('uint8')
    # Use the actual floor POSITION/UV correspondence, including its 90 degree rotation.
    doc,blob=load(DEPS/HALL/'hall_floor.glb');primitive=doc['meshes'][0]['primitives'][0]
    points=np.array(accessor(doc,blob,primitive['attributes']['POSITION']))
    uv=np.array(accessor(doc,blob,primitive['attributes']['TEXCOORD_0']))
    normals=np.array(accessor(doc,blob,primitive['attributes']['NORMAL']))
    use=(points[:,1]>.0799)&(normals[:,1]>.999)
    mapping=np.linalg.lstsq(np.c_[uv[use],np.ones(use.sum())],points[use][:,[0,2]],rcond=None)[0]
    assert np.allclose(np.c_[uv[use],np.ones(use.sum())]@mapping,points[use][:,[0,2]],atol=1e-5)
    yy,xx=np.mgrid[0:1024,0:1024];xz=np.stack([(xx+.5)/2048,(yy+.5)/2048,np.ones_like(xx)],axis=-1)@mapping
    x,z=xz[:,:,0],xz[:,:,1];px,pz=x-.04,z-.18;r=np.hypot(px,pz)
    path=(abs(px)<.35)|(abs(pz)<.35)|((r>.96)&(r<1.66))
    tile_x=np.floor((x+3.3)/.60);tile_z=np.floor((z+3.1)/.60)
    shade=1+.012*np.sin(tile_x*17.13+tile_z*31.7)
    floor=np.array([223,209,180])[None,None,:]*shade[:,:,None]
    edge=np.minimum(np.mod(x+3.3,.6),.6-np.mod(x+3.3,.6))<.006
    edge|=np.minimum(np.mod(z+3.1,.6),.6-np.mod(z+3.1,.6))<.006
    floor[edge]*=.83;floor[path]=[97,128,163]
    rgb[:1024,:1024,:3]=np.clip(floor,0,255).astype('uint8')
    plants=np.asarray(Image.open(ROOT/'assets/rooms/_shared/plants/room_albedo_ao.png').convert('RGBA'))
    for row in plant_tiles:
        sx,sy=row['source'];tx,ty=row['target_px']
        rgb[ty:ty+128,tx:tx+128]=plants[sy*128:(sy+1)*128,sx*128:(sx+1)*128]
    Image.fromarray(rgb).save(KIT/'hall_albedo_ao_n2.png')
    write_json(KIT/'room_skin.json',{'base_shell_commit':SHELL_COMMIT,'same_shell_uv_layout':True,
        'overrides':colors,'floor':{'base':'DFD1B4','path':'6180A3','path_half_width_m':.35,
            'ring_radii_m':[.96,1.66],'world_uv_affine':mapping.tolist(),'tiles_m':.60},
        'plant_tiles':plant_tiles,'plant_reserved_slots':['wood_dark','sage_dark','leather'],
        'note':'Unused furniture slots only. Shared shell UVs, geometry and source atlas are unchanged.'})


def source_variant(name,source,kind,scale=None,plant_tiles=None):
    doc,blob=load(source);original_hash=hashlib.sha256(source.read_bytes()).hexdigest()
    old_palette=json.loads((DEPS/HALL/'palette.json').read_text())['slots']
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            attr=primitive['attributes'];uv=np.array(accessor(doc,blob,attr['TEXCOORD_0']))
            if kind=='hallkit':
                result=np.zeros_like(uv);assigned=np.zeros(len(uv),bool)
                for slot,spec in old_palette.items():
                    lo=np.array(spec['uv_rect_gltf'][:2]);hi=np.array(spec['uv_rect_gltf'][2:])
                    mask=((uv>=lo-1e-6)&(uv<=hi+1e-6)).all(1)
                    target=slot
                    if name in ['sofa_three_seat','armchair'] and slot in ['sage','sage_dark','linen_green','linen','sky']:target='cloth_green'
                    target_rect=PALETTE[target]['uv_rect_gltf'];a=np.array(target_rect[:2]);b=np.array(target_rect[2:])
                    result[mask]=a+(uv[mask]-lo)/(hi-lo)*(b-a);assigned|=mask
                assert assigned.all(),(name,'unmapped UV')
                uv=result
            elif kind=='plant':
                result=np.zeros_like(uv);assigned=np.zeros(len(uv),bool);tiles=np.floor(uv*16).astype(int)
                for row in plant_tiles:
                    tile=np.array(row['source']);mask=(tiles==tile).all(1)
                    result[mask]=(uv[mask]*2048-tile*128+row['target_px'])/2048;assigned|=mask
                assert assigned.all();uv=result
            elif kind=='clock':
                # The reused clock consists of a wooden rim, ivory face and dark hands/ticks.
                points=np.array(accessor(doc,blob,attr['POSITION']))
                roles=np.where(points[:,2]>.065,'iron',np.where(points[:,2]>.05,'linen','oak'))
                uv=np.array([swatch_uv(role) for role in roles])
            replace(doc,blob,attr['TEXCOORD_0'],uv)
            if scale:
                p=np.array(accessor(doc,blob,attr['POSITION']))*scale;replace(doc,blob,attr['POSITION'],p)
                normals=np.array(accessor(doc,blob,attr['NORMAL']))/scale;normals/=np.linalg.norm(normals,axis=1)[:,None]
                replace(doc,blob,attr['NORMAL'],normals)
    bind(doc,name,kind=='plant');save_glb(KIT/(name+'.glb'),doc,blob)
    PROVENANCE[name]={'task':'SGODOT-321','author':'黄忠','virtual_user_id':AUTHOR,
        'source':str(source.relative_to(ROOT)),'source_sha256':original_hash,
        'changes':['N2 atlas/material and UV remap; original geometry retained' if not scale else
            'N2 small table variant: baked scale to diameter .60m, height .75m; original 324 untouched'],
        'scale_xyz':scale or [1,1,1]}


def shape(spec,placement):
    at=spec['at'];pos=placement['position'];yaw=placement['yaw_degrees']
    if spec.get('kind')=='cylinder':p=Point(at[0],at[2]).buffer(spec['radius'],quad_segs=64)
    else:
        w,_,d=spec['size'];p=box(at[0]-w/2,at[2]-d/2,at[0]+w/2,at[2]+d/2)
    return translate(rotate(p,-yaw,origin=(0,0)),pos[0],pos[2])


def navigation(layout):
    obstacles=[]
    for row in layout['placements']:
        for collider in row['colliders']:
            if collider['at'][1]+row['position'][1]-collider.get('height',collider.get('size',[0,0,0])[1])/2>1.82:continue
            obstacles.append((row['name'],shape(collider,row)))
    domain=box(-3.18,-2.98,3.34,3.14)
    union=unary_union([p for _,p in obstacles]);blocked=union.buffer(.25,quad_segs=32)
    free=domain.buffer(-.25).difference(blocked);grid={}
    for iz in range(59):
        for ix in range(62):
            point=(-2.95+ix*.1,-2.70+iz*.1)
            if free.contains(Point(*point)):grid[(ix,iz)]=point
    nearest=lambda p:min(grid,key=lambda k:math.dist(p,grid[k]))
    start=nearest((0,2.5));prev={start:start};queue=deque([start])
    while queue:
        cell=queue.popleft()
        for dx,dz in [(1,0),(-1,0),(0,1),(0,-1)]:
            nxt=(cell[0]+dx,cell[1]+dz)
            if nxt in grid and nxt not in prev and free.covers(LineString([grid[cell],grid[nxt]])):
                prev[nxt]=cell;queue.append(nxt)
    targets=[(a['name'],(a['approach'][0],a['approach'][2])) for a in layout['anchors'] if 'approach' in a]
    available=[grid[k] for k in prev];standing=[grid[start]]
    while len(standing)<16:
        point=max(available,key=lambda p:min(math.dist(p,s) for s in standing))
        assert min(math.dist(point,s) for s in standing)>=.70
        standing.append(point);available.remove(point)
    targets += [('stand_%02d'%i,p) for i,p in enumerate(standing)]
    targets.append(('exit',(0,2.88)))
    routes=[]
    for name,target in targets:
        end=nearest(target);assert end in prev and math.dist(grid[end],target)<.10,(name,target)
        assert free.covers(LineString([grid[end],target])),name
        path=[target];cell=end
        while cell!=start:path.append(grid[cell]);cell=prev[cell]
        path.append(grid[start]);path.reverse();routes.append({'name':name,'points_xz':path})
    base=Point(.04,.18).buffer(.93,quad_segs=64)
    closest=min([(name,p) for name,p in obstacles if name!='sculpture_base'],key=lambda row:row[1].distance(base))
    gap=base.distance(closest[1]);a,b=nearest_points(base,closest[1]);assert gap>=.70
    return {'routes':routes,'standing_positions_xz':standing,'reachable_cells':len(prev),
        'main_min_m':gap,'ring_nearest_module':closest[0],'ring_measurement_xz':[list(a.coords[0]),list(b.coords[0])],
        'capsule_radius_m':.25,'main_capsule_radius_m':.35,'grid_step_m':.1}


def assembly():
    blockout=next(l for l in json.loads((SRC/'blockout_layouts.json').read_text())['layouts'] if l['id']=='B')
    props=json.loads((KIT/'prop_manifest.json').read_text());placed=[]
    def add(name,asset,position,yaw=0,colliders=None):
        placed.append({'name':name,'asset':asset,'position':position,'yaw_degrees':yaw,
            'colliders':colliders or [],'cast_shadow':asset not in ['peace_lily','window_flowerbox']})
    for item in blockout['items']:
        name=item['asset'];info=glb_measure(KIT/(name+'.glb'));lo,hi=np.array(info['bounds'])
        if name=='peace_lily':c=[{'kind':'cylinder','radius':.245,'height':.39,'at':[0,.195,0]}]
        elif name=='small_round_table':c=[{'kind':'cylinder','radius':.30,'height':.75,'at':[0,.375,0]}]
        else:c=[{'size':(hi-lo).tolist(),'at':((lo+hi)/2).tolist()}]
        add(item['name'],name,item['position'],item['yaw_degrees'],c)
    positions={
        'sculpture_base':([.04,.08,.18],0),'sculpture_body':([.04,.48,.18],45),
        'display_niche_1':([-1.65,.08,-2.98],0),'display_niche_2':([1.65,.08,-2.98],0),
        'brochure_rack':([-.10,.08,-2.55],8),'water_dispenser':([3.02,.08,-2.60],0),
        'notice_board':([0,1.63,-2.83],0),'name_plaque':([0,3.08,-2.96],0),
        'call_screen':([-3.04,1.83,0],90),'window_flowerbox':([-2.91,1.06,-1.78],90)}
    for prop in props['assets']:
        name=prop['name'];position,yaw=positions[name];colliders=copy.deepcopy(prop['colliders'])
        if name=='sculpture_base':colliders=[{'kind':'cylinder','at':[0,.20,0],'radius':.93,'height':.40}]
        add(name,name,position,yaw,colliders)
    add('window_flowerbox_2','window_flowerbox',[-2.91,1.06,1.78],90)
    add('wall_clock','wall_clock',[-3.035,2.53,0],90)
    for i,(position,yaw) in enumerate([([-3.04,2.43,2.78],90),([-2.70,2.43,-2.97],0),([2.60,2.43,-2.97],0)],1):
        add('wall_sconce_'+str(i),'wall_sconce',position,yaw)
    anchors=copy.deepcopy(blockout['anchors'])
    # The reusable seating fronts +Z, while Marker3D forward is -Z.
    for anchor in anchors:anchor['yaw_degrees']=(anchor['yaw_degrees']+180)%360
    anchors += [
        {'name':'spawn','position':[0,.08,2.5],'yaw_degrees':180,'module':'hall_floor'},
        {'name':'exit','position':[0,.08,2.88],'yaw_degrees':180,'module':'hall_floor'},
        {'name':'badge_exit','position':[0,.55,3.0],'yaw_degrees':0,'module':'hall_floor'},
        {'name':'cam_default','position':[0,1.1,.35],'yaw_degrees':45,'module':'hall_floor','width_m':6.72,'pitch_degrees':43},
        {'name':'sign_name','position':[0,3.08,-2.925],'yaw_degrees':180,'module':'name_plaque','size':[.88,.23]}]
    assets={name:{'file':name+'.glb',**glb_measure(KIT/(name+'.glb'))} for name in sorted({r['asset'] for r in placed})}
    layout={'task':'SGODOT-321','revision':'v1_room','approved_layout':'B / C48 / 2026-11-02',
        'floor_y':.08,'footprint_m':[6.8,6.4],'atlas':'hall_albedo_ao_n2.png',
        'shared_shell':'res://scenes/shell_hall/shell_hall_art.tscn','shell_commit':SHELL_COMMIT,
        'assets':assets,'placements':placed,'anchors':anchors,'author':'黄忠','virtual_user_id':AUTHOR}
    layout['navigation']=navigation(layout);write_json(KIT/'layout.json',layout)
    shell=json.loads((DEPS/HALL/'shell_asset_stats.json').read_text())
    stats={'room_triangles':sum(assets[r['asset']]['triangles'] for r in placed),
        'room_surfaces':sum(assets[r['asset']]['surfaces'] for r in placed),
        'shared_shell_triangles':shell['scene_triangles'],'shared_shell_surfaces':shell['static_draw_surfaces']}
    stats['scene_triangles']=stats['room_triangles']+stats['shared_shell_triangles']
    stats['scene_surfaces']=stats['room_surfaces']+stats['shared_shell_surfaces']
    assert stats['scene_triangles']<=150000 and stats['scene_surfaces']<=50
    write_json(KIT/'asset_stats.json',stats);print(json.dumps(stats),flush=True)


def main():
    global PALETTE
    dependency_hashes=stage_shell();PALETTE=json.loads((DEPS/HALL/'hall_palette.json').read_text())['slots']
    plant=ROOT/'assets/rooms/_shared/plants/peace_lily.glb';doc,blob=load(plant)
    uv=np.array(accessor(doc,blob,doc['meshes'][0]['primitives'][0]['attributes']['TEXCOORD_0']))
    tiles=np.unique(np.floor(uv*16).astype(int),axis=0);assert len(tiles)<=12
    slots=['wood_dark','sage_dark','leather'];mapping=[]
    for i,tile in enumerate(tiles):
        x,y,_,_=PALETTE[slots[i//4]]['rect_px_top_left']
        mapping.append({'source':tile.tolist(),'target_px':[x+(i%2)*128,y+((i%4)//2)*128]})
    skin(mapping)
    for name in ['sofa_three_seat','armchair','wall_sconce']:
        source_variant(name,DEPS/HALL/(name+'.glb'),'hallkit')
    source_variant('small_round_table',DEPS/HALL/'round_side_table.glb','hallkit',[.60/1.10,.75/1.13425,.60/1.10])
    source_variant('peace_lily',plant,'plant',plant_tiles=mapping)
    source_variant('wall_clock',ROOT/'assets/rooms/post_office/wall_clock.glb','clock')
    props=json.loads((KIT/'prop_manifest.json').read_text())
    for prop in props['assets']:
        path=KIT/prop['file'];doc,blob=load(path);bind(doc,prop['name']);save_glb(path,doc,blob)
        prop['measured']=glb_measure(path)
    props['phase']='Independent props included in user-approved B room';write_json(KIT/'prop_manifest.json',props)
    # No shell or non-plant mesh may sample reserved botanical tiles.
    for path in list(KIT.glob('*.glb'))+list((DEPS/HALL).glob('hall_*.glb')):
        if path.stem=='peace_lily':continue
        doc,blob=load(path)
        for mesh in doc['meshes']:
            for primitive in mesh['primitives']:
                uv=np.array(accessor(doc,blob,primitive['attributes']['TEXCOORD_0']))
                for slot in slots:
                    x,y,w,h=PALETTE[slot]['rect_px_top_left'];low=np.array([x,y])/2048;high=np.array([x+w,y+h])/2048
                    assert not ((uv>low)&(uv<high)).all(1).any(),(path,slot)
    for name,record in PROVENANCE.items():write_json(SRC/'modules'/name/'reuse_provenance.json',record)
    write_json(SRC/'room_dependencies.json',{'shell_commit':SHELL_COMMIT,'hallkit_commit':KIT_COMMIT,
        'unchanged_dependency_sha256':dependency_hashes,'source_base':BASE,'review_pr':597})
    assembly()


if __name__=='__main__':main()
