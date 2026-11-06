"""Reusable 2 m coast modules. Vertex paint; no textures or example layout.
Run Blender under flock ~/gs66-render.lock. Only writes the coast kit / its source.
"""
from pathlib import Path
import hashlib,json,math,struct,sys
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/art'))
import build_decor_assets as K
from verify_chef_sign import load_glb,accessor
OUT=ROOT/'assets/landmarks/_shared/coast_kit';SRC=ROOT/'tools/art/source/coast_kit'
PALETTE=json.loads((SRC/'reference/palette.json').read_text())['colors']
PALETTE.update({'wood':'A3815D','wood_light':'B89972','wood_dark':'795F47','wood_seam':'69543F',
                'rope':'B7A68D','stone_joint':'8B8476'})
ACTOR='8ea32e40-c0ba-4a31-864f-374a6bcbc554'
# z (land - / sea +), y: the SAME six-vertex end profile for all six rocks.
ROCK_PROFILE=[[-.60,0],[-.60,.65],[-.15,.75],[.10,.64],[.45,.33],[.60,0]]
WALL_PROFILE=[[-.32,0],[-.28,1.05],[-.32,1.12],[-.32,1.20],[.32,1.20],[.32,1.12],[.28,1.05],[.38,0]]
records={}

def face_roles(o,roles):
    o.data.materials.clear()
    for role in roles:o.data.materials.append(K.MATS[role])
    for face in o.data.polygons:
        # Up-facing caps are warm mineral highlights; front planes stay darker.
        n=face.normal
        face.material_index=1 if n.z>.45 else 2 if n.z<-.2 else (3 if len(roles)>3 and face.index%7==3 else 0)

def port(name,at,outward,profile,family):
    return dict(name=name,position=at,outward=outward,up=[0,1,0],profile=profile,family=family)

def rock_module(kind,high):
    n=len(ROCK_PROFILE);sections=[];start=[];end=[]
    samples=[0,.12,.25,.36,.50,.62,.72,.88,1]
    for i,t in enumerate(samples):
        wave=math.sin(math.pi*t)**2;points=[]
        fracture=max(0,1-abs(t-.36)/.08)+.65*max(0,1-abs(t-.72)/.06)
        for j,(depth,height) in enumerate(ROCK_PROFILE):
            bump=(.45 if high else .05)*wave*[0,.55,1,.8,.22,0][j]
            d=depth+(.06 if j in [3,4] else 0)*math.sin(t*math.tau)*wave
            # Two shallow geological breaks, modelled into broad mineral planes.
            # Their influence vanishes at both ports; the end profiles stay exact.
            y=height+bump-.10*fracture*wave*[0,.20,.95,.85,.3,0][j]
            d-=.06*fracture*wave*[0,0,.3,.8,1,0][j]
            if kind=='straight':x=-1+2*t;z=d
            else:
                angle=t*math.pi/2
                sx,cz=math.sin(angle),math.cos(angle)
                if i==0:sx,cz=0,1
                if i==len(samples)-1:sx,cz=1,0
                if kind=='outer':x=-1+(1+d)*sx;z=-1+(1+d)*cz
                else:x=-1+(1-d)*sx;z=1-(1-d)*cz
            points.append((x,y,z))
        sections.append(points)
    points=[p for section in sections for p in section]
    faces=[tuple(reversed(range(n))),tuple(range((len(samples)-1)*n,len(samples)*n))]
    for i in range(len(samples)-1):
        for j in range(n):faces.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
    o=K.mesh('Continuous fractured shore / '+kind+(' high' if high else ' low'),points,faces,'rock')
    face_roles(o,['rock','rock_light','rock_shadow','rock_warm'])
    end_at=[1,0,0] if kind=='straight' else [0,0,-1 if kind=='outer' else 1]
    end_normal=[1,0,0] if kind=='straight' else [0,0,-1 if kind=='outer' else 1]
    return {'family':'shore_rock','nominal_module_m':2,'height_variant':'high' if high else 'low','crest_height_m':1.2 if high else .8,'water_side':'local +Z at inlet; follows turning tangent',
            'ports':[port('in',[-1,0,0],[-1,0,0],sections[0],'shore_rock'),port('out',end_at,end_normal,sections[-1],'shore_rock')],
            'note':'Both height variants share exactly the same end profiles. Raised mass is internal to each module; no transition piece is required.'}

def scatter(index):
    source=ROOT/'assets/landmarks/alcatraz_island'/('alc_rock_'+chr(97+index)+'.glb')
    doc,data=load_glb(source);p=doc['meshes'][0]['primitives'][0]
    pos=accessor(doc,data,p['attributes']['POSITION']);normals=accessor(doc,data,p['attributes']['NORMAL']);idx=[v[0] for v in accessor(doc,data,p['indices'])]
    dims=[(1.0,.55,.85),(1.4,.85,1.1),(1.9,.95,1.4)][index]
    low=[min(v[k] for v in pos) for k in range(3)];high=[max(v[k] for v in pos) for k in range(3)];scale=[dims[k]/(high[k]-low[k]) for k in range(3)]
    points=[tuple((v[k]-low[k])*scale[k]-(dims[k]/2 if k!=1 else 0) for k in range(3)) for v in pos]
    # Keep the accepted indexed winding. GLB colour/normal splits disconnect
    # coincident vertices; recalculating each disconnected face would flip it.
    data=bpy.data.meshes.new('Preserved fractured rock topology')
    data.from_pydata([K.v(v) for v in points],[],[idx[i:i+3] for i in range(0,len(idx),3)]);data.update()
    o=bpy.data.objects.new('Resized fractured Alcatraz shore rock',data);K.CURRENT.objects.link(o)
    for face in data.polygons:face.use_smooth=True
    face_roles(o,['rock','rock_light','rock_shadow','rock_warm'])
    transformed=[K.v(tuple(n[k]/scale[k] for k in range(3))).normalized() for n in normals]
    o.data.normals_split_custom_set([transformed[loop.vertex_index] for loop in o.data.loops])
    return {'family':'scatter','intended_dimensions_m':dims,'ports':[],
            'reuse':{'source_file':source.relative_to(ROOT).as_posix(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'changes':'resized to kit scale, recoloured to island palette; source geometry and source file untouched'}}

def seawall():
    # Leave both accepted eight-vertex end profiles untouched. Interior cap
    # projects 14 cm beyond the upper body; grooves taper into the end collars.
    inside=[[-.32,0],[-.28,1.05],[-.42,1.08],[-.42,1.20],[.42,1.20],[.42,1.08],[.28,1.05],[.38,0]]
    edges=[];offsets=[];outline=[]
    for j in range(8):
        edge=[inside[j]]
        if j in [0,6]:
            levels=[.3,.6,.9] if j==0 else [.9,.6,.3]
            for y in levels:
                bands=[(y-.02,0),(y-.01,.018),(y+.01,.018),(y+.02,0)]
                if j==6:bands.reverse()
                for height,inset in bands:
                    depth=(-.32+.04*height/1.05+inset) if j==0 else (.38-.10*height/1.05-inset)
                    edge.append([depth,height])
        edge.append(inside[(j+1)%8]);offsets.append(len(outline));outline.extend(edge[:-1]);edges.append(edge)
    n=len(outline);left=[(-1,y,z) for z,y in WALL_PROFILE];right=[(1,y,z) for z,y in WALL_PROFILE]
    pts=left+[(-.90,y,z) for z,y in outline]+[(.90,y,z) for z,y in outline]+right
    right_start=8+2*n
    faces=[tuple(reversed(range(8))),tuple(range(right_start,right_start+8))]
    for j,edge in enumerate(edges):
        ids=[(offsets[j]+k)%n for k in range(len(edge))]
        for a,b in zip(ids,ids[1:]):
            faces.append((j,8+a,8+b))
            faces.append((right_start+j,8+n+b,8+n+a))
        faces.append((j,8+ids[-1],(j+1)%8))
        faces.append((right_start+j,right_start+(j+1)%8,8+n+ids[-1]))
    for j in range(n):faces.append((8+j,8+(j+1)%n,8+n+(j+1)%n,8+n+j))
    o=K.mesh('Concrete wall / overhanging coping and three recessed courses',pts,faces,'stone')
    face_roles(o,['stone','stone_light','stone_shade']);o.data.materials.append(K.MATS['stone_joint'])
    for face in o.data.polygons:
        if abs(face.center.x)<.90 and abs(face.normal.z)<.2 and any(abs(face.center.z-y)<.012 for y in [.3,.6,.9]):face.material_index=3
    return {'family':'seawall','nominal_module_m':2,'top_y':1.2,'coping_width_m':.84,'horizontal_joint_levels_m':[.3,.6,.9],
            'ports':[port('in',[-1,0,0],[-1,0,0],left,'seawall'),port('out',[1,0,0],[1,0,0],right,'seawall')]}

def dock(end=False,bollard=False):
    # #830 v1.1: nominal 1.8 x .18 m boards, .9 m half stagger,
    # .012 m dark joints. Crop the pattern inside the existing 2 m module.
    # Partition one top plane, rather than stacking coplanar faces or making
    # a closed box for each board; the original port silhouette stays exact.
    slab=K.box('Deck / closed outer fascia and underside',(0,1.14,0),(2,.12,2),'wood_dark',0)
    bm=bmesh.new();bm.from_mesh(slab.data)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.normal.z>.5],context='FACES')
    bm.to_mesh(slab.data);bm.free()
    outer=[(-1,1.2,-1),(-1,1.2,1),(1,1.2,1),(1,1.2,-1)]
    inner=[(-.99,1.2,-.99),(-.99,1.2,.99),(.99,1.2,.99),(.99,1.2,-.99)]
    def upward(o):
        # An open coplanar piece has no volume for recalc to choose an outside.
        bm=bmesh.new();bm.from_mesh(o.data)
        bmesh.ops.reverse_faces(bm,faces=[f for f in bm.faces if f.normal.z<0])
        bm.to_mesh(o.data);bm.free()
    upward(K.mesh('Deck / narrow edge strip',outer+inner,[(i,(i+1)%4,(i+1)%4+4,i+4) for i in range(4)],'wood_light'))
    def tile(label,left,right,back,front,shade):
        upward(K.mesh(label,[(left,1.2,back),(left,1.2,front),(right,1.2,front),(right,1.2,back)],[(0,1,2,3)],shade))
    gap=.012;planks=[]
    for row in range(11):
        z0=-.99+row*.18;z1=z0+.18
        back=z0+(gap/2 if row else 0);front=z1-(gap/2 if row<10 else 0)
        joints=[-.9,.9] if row%2==0 else [0.0]
        edges=[-.99]+[v for joint in joints for v in [joint-gap/2,joint+gap/2]]+[.99]
        for i,(left,right) in enumerate(zip(edges,edges[1:])):
            seam=i%2==1
            tone=(row*5+(i//2)*3)%9
            shade='wood_seam' if seam else 'plank_tone_'+str(tone)
            tile(('Joint' if seam else 'Board')+' row %02d part %02d'%(row,i),left,right,back,front,shade)
            if not seam:planks.append({'row':row,'bounds_xz':[left,right,back,front],'linear_tone_factor':1+[-.14,-.10,-.07,-.04,0,.04,.07,.10,.14][tone]})
        if row<10:tile('Continuous long joint %02d'%row,-.99,.99,z1-gap/2,z1+gap/2,'wood_seam')
    for z in [-.72,.72]:
        K.box('Continuous longitudinal beam',(0,1.015,z),(2,.13,.14),'wood_dark',0)
        for x in [-.66,.66]:K.box('Corner timber pile', (x,.49,z),(.16,.98,.16),'wood_dark',0)
    for x in [-.66,.66]:K.box('Cross support over corner pile row',(x,.90,0),(.18,.12,1.62),'wood',0)
    if end:
        # End fascia stays INSIDE the 2 m tile; no accidental longer final segment.
        K.box('Terminal end fascia',(.96,1.025,0),(.08,.11,2),'wood_dark',0)
        for z in [-.82,.82]:K.box('Low terminal bumper',(.87,1.27,z),(.18,.14,.18),'wood',.015)
    if bollard:
        K.cylinder('Mooring bollard foot',(0,1.235,.73),.19,.07,'dark',segments=6)
        K.cylinder('Mooring bollard stem',(0,1.49,.73),.10,.44,'dark',top=.12,segments=6)
        K.box('Mooring bollard transverse head',(0,1.72,.73),(.48,.11,.15),'dark',.015)
        bpy.ops.mesh.primitive_torus_add(major_radius=.21,minor_radius=.025,major_segments=10,minor_segments=3,location=K.v((.50,1.23,.55)))
        K.finish(bpy.context.object,'Single quiet rope coil','rope',True)
    # Explicit profiles of every beam/plank end, not support piles between seams.
    profile=[]
    for x in [-1,1]:
        points=[(x,y,z) for y,z in [(1.08,-1),(1.20,-1),(1.20,1),(1.08,1)]]
        for z in [-.72,.72]:points.extend([(x,.95,z-.07),(x,1.08,z-.07),(x,1.08,z+.07),(x,.95,z+.07)])
        profile.append(points)
    ports=[port('in',[-1,1.2,0],[-1,0,0],profile[0],'dock')]
    if not end:ports.append(port('out',[1,1.2,0],[1,0,0],profile[1],'dock'))
    return {'family':'dock','nominal_module_m':2,'deck_size_m':[2,2],'deck_y':1.2,'ports':ports,'terminal':end,'mooring_bollard':bollard,
            'planks':len(planks),'plank_rows':11,'board_nominal_size_m':[1.8,.18],'half_stagger_m':.9,
            'plank_width_range_m':[.168,.174],'joint_width_m':gap,'plank_patches':planks,
            'wood_reference':{'pr':830,'head':'5f9b59b8','tone_strength':.14,'base':'#A3815D','light':'#B89972','dark':'#795F47','joint':'#69543F'},
            'pile_count':4,'pile_centres':[[x,0,z] for z in [-.72,.72] for x in [-.66,.66]],'pile_width_m':.16,
            'placement_y':'desired walking height minus 1.2 m; piles may extend underwater'}

def buoy():
    profile=[(.09,0),(.22,.13),(.28,.30),(.28,.45),(.22,.67),(.09,.78)]
    o=K.lathe('Buoy / closed floating body',profile,'sign_cream',segments=10)
    o.data.materials.append(K.MATS['bridge']);o.data.materials.append(K.MATS['dark'])
    for p in o.data.polygons:
        p.material_index=1 if .29<p.center.z<.46 else 2 if p.center.z<.13 else 0
    K.cylinder('Buoy / marker stem',(0,.91,0),.035,.28,'dark',segments=8)
    bpy.ops.mesh.primitive_torus_add(major_radius=.095,minor_radius=.018,major_segments=10,minor_segments=4,location=K.v((0,1.12,0)),rotation=(math.pi/2,0,0))
    K.finish(bpy.context.object,'Buoy / handling ring','dark',True)
    return {'family':'buoy','waterline_y':.30,'ports':[],'placement_y':'water height minus 0.30 m; static prototype, no bobbing animation'}

def stairs():
    for i in range(8):
        height=round(1.2-i*.15,3)
        o=K.box('Solid concrete tread %02d'%(i+1),(0,height/2,-.875+i*.25),(2,height,.25),'stone',0)
        face_roles(o,['stone','stone_light','stone_shade'])
    return {'family':'stairs','nominal_module_m':2,'width_m':2,'run_m':2,'riser_m':.15,'tread_m':.25,'steps':8,'top_y':1.2,'lowest_tread_y':.15,'ports':[{'name':'land','position':[0,1.2,-1],'outward':[0,0,-1],'family':'landing_2m'},{'name':'water','position':[0,.15,1],'outward':[0,0,1],'family':'water_access'}]}

def rename_mesh(path,name):
    raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);tail=raw[20+n:]
    doc['meshes'][0]['name']=name+'_mobile';encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)

def encode_surface_codes(path,rock):
    # Keep positions, normals, indices and the warm RGB paint byte-identical.
    # Repack only COLOR_0 from VEC3 to VEC4; alpha is a shader tag, not opacity.
    doc,old=load_glb(path);primitive=doc['meshes'][0]['primitives'][0];index=primitive['attributes']['COLOR_0'];access=doc['accessors'][index]
    colors=accessor(doc,old,index);view_index=access['bufferView'];payload=bytearray()
    palette=[K.rgb(PALETTE[k]) for k in ['rock','rock_light','rock_shadow','rock_warm']]
    for c in colors:
        code=(min(range(4),key=lambda j:sum((c[k]-palette[j][k])**2 for k in range(3)))+1)/8 if rock else .75
        payload.extend(struct.pack('<4f',*c[:3],code))
    binary=bytearray()
    for i,view in enumerate(doc['bufferViews']):
        part=bytes(payload) if i==view_index else old[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
        binary.extend(b'\0'*(-len(binary)%4));view['byteOffset']=len(binary);view['byteLength']=len(part)
        if i==view_index:view.pop('byteStride',None)
        binary.extend(part)
    access['type']='VEC4';access['componentType']=5126;access.pop('normalized',None);access['byteOffset']=0
    binary.extend(b'\0'*(-len(binary)%4));doc['buffers'][0]['byteLength']=len(binary)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary)

def main():
    retained=json.loads((OUT/'manifest.json').read_text())['assets']
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0;K.OUT=OUT
    for role,value in PALETTE.items():
        m=bpy.data.materials.new(role);m.diffuse_color=(*K.rgb(value),1);m.use_nodes=True
        p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=m.diffuse_color;p.inputs['Roughness'].default_value=.94;p.inputs['Specular IOR Level'].default_value=.15;K.MATS[role]=m
    # Match #830's +/-14% tone in linear space, without quantizing to hex.
    for i,tone in enumerate([-.14,-.10,-.07,-.04,0,.04,.07,.10,.14]):
        m=K.MATS['wood'].copy();m.name='plank_tone_'+str(i)
        m.diffuse_color=(*[v*(1+tone) for v in K.rgb(PALETTE['wood'])],1)
        m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=m.diffuse_color
        K.MATS[m.name]=m
    material=bpy.data.materials.new('Coast kit / matte vertex paint');material.use_nodes=True;material.use_backface_culling=True
    shader=material.node_tree.nodes['Principled BSDF'];shader.inputs['Roughness'].default_value=.94;shader.inputs['Specular IOR Level'].default_value=.15
    vc=material.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';material.node_tree.links.new(vc.outputs['Color'],shader.inputs['Base Color'])
    builders=[]
    for kind in ['straight','outer','inner']:
        for high in [False,True]:builders.append(('coast_rock_'+kind+('_high' if high else '_low'),lambda k=kind,h=high:rock_module(k,h)))
    for i in range(3):builders.append(('coast_scatter_'+chr(97+i),lambda index=i:scatter(index)))
    builders += [('coast_seawall',seawall),('coast_dock_straight',dock),('coast_dock_end',lambda:dock(end=True)),('coast_dock_bollard',lambda:dock(bollard=True)),('coast_buoy',buoy),('coast_water_steps',stairs)]
    for name,build in builders:
        K.begin(name,[1,1],400,generator='tools/art/build_coast_kit.py',author='赵云',virtual_user_id=ACTOR,pivot='module construction origin, Y=0 base',collision='none; consuming scene owns physics')
        meta=build();bpy.context.view_layer.update()
        path=OUT/(name+'.glb')
        if name in ['coast_buoy','coast_water_steps']:
            entry=retained[name];assert hashlib.sha256(path.read_bytes()).hexdigest()==entry['sha256']
        else:
            entry=K.export_asset(name,K.CURRENT,material);rename_mesh(path,name)
            rock=meta['family'] in ['shore_rock','scatter'];encode_surface_codes(path,rock)
            entry.update(meta);entry.update(file=name+'.glb',sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytes=path.stat().st_size,source='tools/art/source/coast_kit/coast_kit.blend',material='coast_cool_gray.tres' if rock else 'coast_warm_sand.tres')
        records[name]=entry;print('COAST_KIT',name,entry['triangles'],entry['bounds'],flush=True)
    manifest={'author':'赵云','virtual_user_id':ACTOR,'revision':'v1.2','module_grid_m':2,'axes':'metres, Y up; straight coast +X tangent, +Z water / -Z land','material_contract':{'vertex_color_is_srgb':False,'roughness':.94,'specular':.15,'metallic':0,'textures':False,'passes':1,'keep_imported_material':True,'vertex_alpha':'opaque surface tag: 1/8 rock base, 2/8 light, 3/8 shadow, 4/8 warm, 6/8 wettable solid'},'rock_palettes':{'selector':'rock_palette','warm_sand':0,'cool_gray_brown':1,'cool_reference':'SGODOT-424 #801 v3 af319757: #777A75 / #93958B / #515B59'},'wet_band':{'water_level_default':.15,'height_above_water_m':.25,'strength':.38,'space':'world; follows translated/scaled instances','foam_compatibility':'opaque underlying surface; existing #824 foam remains an independent transparent layer at water + 0.018m'},'palette_srgb':PALETTE,'reference':json.loads((SRC/'reference/provenance.json').read_text()),'assets':records,'example_layout_included':False}
    for path in [OUT/'manifest.json',SRC/'asset_stats.json']:path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'coast_kit.blend'),compress=True)

if __name__=='__main__':main()
