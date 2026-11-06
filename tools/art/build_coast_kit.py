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
    n=len(WALL_PROFILE);pts=[(x,y,z) for x in [-1,1] for z,y in WALL_PROFILE]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
    o=K.mesh('Battered concrete wall / continuous coping',pts,faces,'stone');face_roles(o,['stone','stone_light','stone_shade'])
    return {'family':'seawall','nominal_module_m':2,'top_y':1.2,'ports':[port('in',[-1,0,0],[-1,0,0],pts[:n],'seawall'),port('out',[1,0,0],[1,0,0],pts[n:],'seawall')]}

def dock(end=False,bollard=False):
    # Eight full-width planks meet without open slots. Alternating paint is the seam.
    for i in range(8):
        color=['wood','wood_light','wood','wood','wood_light','wood','wood_dark','wood'][i]
        K.box('Deck plank %02d'%i,(-.875+.25*i,1.14,0),(.25,.12,2),color,0)
    for z in [-.72,.72]:
        K.box('Continuous longitudinal beam',(0,1.015,z),(2,.13,.14),'wood_dark',0)
        K.cylinder('Round timber pile',(0,.49,z),.11,.98,'wood_dark',top=.095,segments=6)
    K.box('Central cross support',(0,.90,0),(.18,.12,1.62),'wood',0)
    if end:
        # End fascia stays INSIDE the 2 m tile; no accidental longer final segment.
        K.box('Terminal end fascia',(.96,1.025,0),(.08,.11,2),'wood_dark',0)
        for z in [-.82,.82]:K.box('Low terminal bumper',(.87,1.27,z),(.18,.14,.18),'wood',.015)
    if bollard:
        K.cylinder('Mooring bollard foot',(0,1.235,.73),.19,.07,'dark',segments=8)
        K.cylinder('Mooring bollard stem',(0,1.49,.73),.10,.44,'dark',top=.12,segments=8)
        K.box('Mooring bollard transverse head',(0,1.72,.73),(.48,.11,.15),'dark',.015)
        bpy.ops.mesh.primitive_torus_add(major_radius=.21,minor_radius=.025,major_segments=12,minor_segments=3,location=K.v((.50,1.23,.55)))
        K.finish(bpy.context.object,'Single quiet rope coil','wood_light',True)
    # Explicit profiles of every beam/plank end, not support piles between seams.
    profile=[]
    for x in [-1,1]:
        points=[(x,y,z) for y,z in [(1.08,-1),(1.20,-1),(1.20,1),(1.08,1)]]
        for z in [-.72,.72]:points.extend([(x,.95,z-.07),(x,1.08,z-.07),(x,1.08,z+.07),(x,.95,z+.07)])
        profile.append(points)
    ports=[port('in',[-1,1.2,0],[-1,0,0],profile[0],'dock')]
    if not end:ports.append(port('out',[1,1.2,0],[1,0,0],profile[1],'dock'))
    return {'family':'dock','nominal_module_m':2,'deck_size_m':[2,2],'deck_y':1.2,'ports':ports,'terminal':end,'mooring_bollard':bollard,'placement_y':'desired walking height minus 1.2 m; piles may extend underwater'}

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

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0;K.OUT=OUT
    for role,value in PALETTE.items():
        m=bpy.data.materials.new(role);m.diffuse_color=(*K.rgb(value),1);m.use_nodes=True
        p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=m.diffuse_color;p.inputs['Roughness'].default_value=.94;p.inputs['Specular IOR Level'].default_value=.15;K.MATS[role]=m
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
        entry=K.export_asset(name,K.CURRENT,material);path=OUT/(name+'.glb');rename_mesh(path,name)
        entry.update(meta);entry.update(file=name+'.glb',sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytes=path.stat().st_size,source='tools/art/source/coast_kit/coast_kit.blend')
        records[name]=entry;print('COAST_KIT',name,entry['triangles'],entry['bounds'],flush=True)
    manifest={'author':'赵云','virtual_user_id':ACTOR,'module_grid_m':2,'axes':'metres, Y up; straight coast +X tangent, +Z water / -Z land','material_contract':{'vertex_color_is_srgb':False,'roughness':.94,'specular':.15,'metallic':0,'textures':False},'palette_srgb':PALETTE,'reference':json.loads((SRC/'reference/provenance.json').read_text()),'assets':records,'example_layout_included':False}
    for path in [OUT/'manifest.json',SRC/'asset_stats.json']:path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'coast_kit.blend'),compress=True)

if __name__=='__main__':main()
