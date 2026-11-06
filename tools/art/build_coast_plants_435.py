"""SGODOT-435: coastal vegetation, closed vertex-painted meshes and paired LODs.
Run every Blender invocation under flock ~/gs66-render.lock.
"""
from pathlib import Path
import hashlib,json,math,sys
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/art'))
import build_decor_assets as K
import build_alcatraz_trees_cd_424 as T
SRC=ROOT/'tools/art/source/coast_plants_435';OUT=ROOT/'assets/landmarks/_shared/coast_plants'
ACTOR='8ea32e40-c0ba-4a31-864f-374a6bcbc554'
COLORS={'grass':'869955','grass_light':'ABB273','grass_dark':'637D43','dry_tip':'C4B780',
 'ice':'6F8E62','ice_light':'99AE78','ice_shadow':'527553','ice_tip':'B0A67D',
 'pink':'CA74A3','pink_light':'E0A0BD','pink_dark':'AD5D8D','pollen':'E5C476',
 'sage':'82967A','sage_light':'A4B392','sage_dark':'647E64',
 'shrub':'7E914E','shrub_light':'A1AC68','shrub_dark':'607A43',
 'cypress':'71894F','cypress_light':'91A367','cypress_dark':'536E43',
 'palm':'859848','palm_light':'A9B25F','palm_dark':'637B3B',
 'wood':'A3815D','wood_light':'B89972','wood_dark':'795F47'}

def blade(name,a,b,width,color,thickness=.025):
    a,b=Vector(a),Vector(b);d=b-a;s=Vector((-d.z,0,d.x)).normalized()*width/2
    mid=a.lerp(b,.52);up=Vector((0,thickness,0))
    return K.mesh(name,[a,mid+s,b,mid-s,mid+up,mid-up*.22],
        [(4,i,(i+1)%4) for i in range(4)]+[(5,(i+1)%4,i) for i in range(4)],color,True)

def grass(variant):
    count=18 if variant=='a' else 25
    for i in range(count):
        theta=i*2.399963;ring=.055+.045*(i%3);root=Vector((ring*math.cos(theta),0,ring*math.sin(theta)))
        h=(.43+.09*(i%4)) if variant=='a' else (.22+.065*(i%4))
        reach=(.14+.055*(i%3)) if variant=='a' else (.26+.045*(i%3))
        tip=root+Vector((reach*math.cos(theta)+.10,h,reach*math.sin(theta)))
        blade('Sea grass / folded blade %02d'%i,root,tip,.038 if variant=='a' else .055,['grass','grass_light','grass_dark'][i%3],.012)
    if variant=='a':
        for i in range(3):
            x=-.10+i*.085;z=.03*math.sin(i*2);h=.66+i*.06
            K.rod('Grass / slender seed stalk '+str(i),(x,0,z),(x+.07,h,z),.008,'grass_dark',segments=3,top=.004)
            K.rod('Grass / pale narrow seed '+str(i),(x+.063,h-.095,z),(x+.075,h+.055,z),.022,'dry_tip',segments=5,top=.005)

def flower(name,c,r,phase):
    c=Vector(c)
    for j in range(10):
        t=j*math.tau/10+phase;u=Vector((math.cos(t),.14,math.sin(t)));v=Vector((-u.z,0,u.x))
        pts=[c+u*.016,c+u*r*.7+v*r*.13,c+u*r,c+u*r*.7-v*r*.13,c+u*r*.55+Vector((0,.014,0))]
        K.mesh(name+' / slender petal %02d'%j,pts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(0,3,2),(0,2,1)],'pink_light' if j%3==0 else 'pink',True)
    mid=c+Vector((0,.012,0));points=[mid+Vector((0,.013,0)),mid-Vector((0,.008,0))]+[mid+Vector((.0225*math.cos(j*math.tau/6),0,.0225*math.sin(j*math.tau/6))) for j in range(6)]
    K.mesh(name+' / warm centre',points,[(0,2+j,2+(j+1)%6) for j in range(6)]+[(1,2+(j+1)%6,2+j) for j in range(6)],'pollen',True)

def iceplant(variant):
    centres=[(-.22,-.12),(.20,-.11),(-.09,.16),(.23,.17)] if variant=='a' else [(-.40,-.07),(-.14,.12),(.14,-.06),(.40,.10)]
    count=24 if variant=='a' else 22
    for i in range(count):
        cx,cz=centres[i%4];theta=(i//4)*1.14+(i%4)*.65
        root=Vector((cx, .009,cz));length=.15+(i%3)*.045
        tip=root+Vector((length*math.cos(theta),.03+.015*(i%2),length*math.sin(theta)))
        blade('Ice plant / fleshy lance %02d'%i,root,tip,.065,['ice','ice_light','ice_shadow'][i%3],.035)
    blooms=[(-.20,.10,-.07,.105),(.22,.11,.12,.115)] if variant=='a' else [(-.39,.11,-.02,.095),(.03,.10,-.05,.10),(.35,.12,.11,.10)]
    for i,(x,y,z,r) in enumerate(blooms):flower('Ice plant / pink bloom '+str(i),(x,y,z),r,i*.5)

def ico(name,at,size,role):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1)
    o=bpy.context.object;o.location=K.v(at);o.scale=(size[0]/2,size[2]/2,size[1]/2)
    return K.finish(o,name,role,True)

def shrub(variant):
    role='sage' if variant=='a' else 'shrub'
    specs=[(-.27,.29,-.04,.55),(.20,.36,-.10,.67),(-.02,.49,.10,.63),(.33,.22,.23,.48),(-.31,.21,.26,.46),(.02,.24,-.30,.47)]
    if variant=='b':specs=[(x*.72,y*1.3,z*.78,s*.94) for x,y,z,s in specs]+[(.04,.75,.035,.45)]
    for i,(x,y,z,s) in enumerate(specs):
        ico('Coastal '+role+' / broad foliage '+str(i),(x,y,z),(s,s*.76,s*.85),role+['_dark','','_light'][i%3])
    for i,end in enumerate([(-.22,.30,0),(.22,.38,-.10),(.01,.52,.10)]):
        K.rod('Coastal '+role+' / short woody fork '+str(i),(0,0,0),end,.035,'wood_dark',segments=4,top=.017)

def canopy(name,at,size,far,color):
    # Same envelope and latitude landmarks, solid caps at both LODs.
    n=8 if far else 12;cx,cy,cz=at;rx,ry,rz=[v/2 for v in size]
    rings=[(-.12,.90),(.12,1)] if far else [(-.32,.62),(-.12,.90),(.12,1),(.32,.64)]
    pts=[(cx,cy-ry,cz)]
    for h,r in rings:
        for j in range(n):
            a=j*math.tau/n;pts.append((cx+rx*r*math.cos(a),cy+ry*h*2,cz+rz*r*math.sin(a)))
    pts.append((cx+.03*rx,cy+ry,cz));top=len(pts)-1
    faces=[(0,1+(j+1)%n,1+j) for j in range(n)]
    for row in range(len(rings)-1):
        for j in range(n):
            a=1+row*n+j;b=1+row*n+(j+1)%n;faces.append((a,b,b+n,a+n))
    last=1+(len(rings)-1)*n
    faces.extend((last+j,last+(j+1)%n,top) for j in range(n))
    return K.mesh(name,pts,faces,color,True)

def tetra(name,a,b,r,color):
    a,b=Vector(a),Vector(b);u=(b-a).normalized().cross(Vector((0,0,1))).normalized()*r;v=(b-a).normalized().cross(u).normalized()*r*.4
    return K.mesh(name,[a+u,a-u,b+v,b-v],[(0,1,2),(1,0,3),(1,3,2),(0,2,3)],color,True)

def cypress(far):
    parts=[]
    for i,(at,size,role) in enumerate([((-.30,3.65,-.15),(2.9,1.20,2.25),'cypress_dark'),((.85,4.55,.15),(3.7,1.35,2.65),'cypress'),((1.9,5.25,.02),(3.1,1.10,2.35),'cypress_light')]):
        parts.append(('crown_'+str(i),canopy('Monterey cypress / windswept crown '+str(i),at,size,far,role),role))
    rings=[((0,0,0),.23,.20),((.25,2.3,-.03),.17,.14),((1.52,4.95,.03),.06,.05)]
    parts.append(('trunk',T.loft('Monterey cypress / bent trunk',rings,3 if far else 8,'wood_dark'),'wood_dark'))
    for i,(a,b) in enumerate([((.17,1.8,0),(-.38,3.61,-.12)),((.45,2.8,0),(.85,4.45,.12))]):
        o=tetra('Cypress / fork '+str(i),a,b,.13,'wood') if far else K.rod('Cypress / spreading fork '+str(i),a,b,.12,'wood',segments=6,top=.045)
        parts.append(('branch_'+str(i),o,'wood'))
    return parts

def palm_frond(index,far):
    # Coastal fan palm: broad folded fans stay legible from the default camera.
    # Same root and outer arc; near outline has shallow finger notches.
    angle=index*math.tau/7+.22;u=Vector((math.cos(angle),0,math.sin(angle)));side=Vector((-u.z,0,u.x))
    base=Vector((.65,5.15,0));fanbase=base+u*.72+Vector((0,[.50,-.25,.80,-.45,.45,.90,-.30][index],0))
    radius=1.22+.08*(index%3);steps=4 if far else 16
    outline=[base]
    for j in range(steps+1):
        a=math.radians(-65+130*j/steps);r=radius*(.88 if not far and j%2 else 1)
        point=fanbase+u*(math.cos(a)*r)+side*(math.sin(a)*r)
        point.y-=.42*math.cos(a)+.12*(index%2)
        outline.append(point)
    hub=fanbase+u*.40+Vector((0,.11,0));n=len(outline)
    pts=outline+[hub,hub-Vector((0,.07,0))]
    faces=[(n,j,(j+1)%n) for j in range(n)]+[(n+1,(j+1)%n,j) for j in range(n)]
    o=K.mesh('Palm / pleated fan '+str(index),pts,faces,'palm',False)
    o.data.materials.append(K.MATS['palm_light']);o.data.materials.append(K.MATS['palm_dark'])
    for f in o.data.polygons:f.material_index=(1 if f.index%4==0 else 0) if f.index<n else 2
    return o

def palm(far):
    parts=[]
    rings=[((0,0,0),.16,.16),((.25,2.6,.02),.125,.125),((.65,5.15,0),.095,.095)]
    parts.append(('trunk',T.loft('Palm / gently leaning trunk',rings,6 if far else 8,'wood'),'wood'))
    for i in range(7):parts.append(('frond_'+str(i),palm_frond(i,far),'palm'))
    hub=tetra('Palm / far growing crown',(.65,5.0,0),(.65,5.32,0),.15,'palm_dark') if far else ico('Palm / compact growing crown',(.65,5.15,0),(.30,.34,.30),'palm_dark')
    parts.append(('hub',hub,'palm_dark'))
    return parts

def apply_and_paint(o,role,mat):
    T.apply(o);T.palette_paint(o,role,mat)

def main():
    OUT.mkdir(parents=True,exist_ok=True);SRC.mkdir(parents=True,exist_ok=True);(SRC/'.gdignore').touch()
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
    T.OUT=OUT;T.PALETTE=COLORS
    for role,value in COLORS.items():
        m=bpy.data.materials.new(role);m.diffuse_color=(*K.rgb(value),1);K.MATS[role]=m
    mat=bpy.data.materials.new('Coast plants / opaque matte vertex colour');mat.use_nodes=True;mat.use_backface_culling=True
    p=mat.node_tree.nodes['Principled BSDF'];p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18
    vc=mat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';mat.node_tree.links.new(vc.outputs['Color'],p.inputs['Base Color'])
    entries={};groups=[]
    for family,build in [('grass',grass),('iceplant',iceplant),('shrub',shrub)]:
        for variant in ['a','b']:
            name='coast_'+family+'_'+variant;K.begin(name,[1,1],400,author='赵云',virtual_user_id=ACTOR)
            build(variant);bpy.context.view_layer.update();parts=[]
            for i,o in enumerate(list(K.CURRENT.objects)):
                role=o.data.materials[0].name;apply_and_paint(o,role,mat);parts.append((str(i),o,role))
            lo=Vector([min(v.co[k] for _,o,_ in parts for v in o.data.vertices) for k in range(3)])
            hi=Vector([max(v.co[k] for _,o,_ in parts for v in o.data.vertices) for k in range(3)])
            offset=Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,-lo.z))
            for _,o,_ in parts:
                for v in o.data.vertices:v.co+=offset
            entries[name]=T.export(name,parts,400);entries[name].update(family=family,lod='single',multimesh=True)
    for base,build in [('coast_cypress',cypress),('coast_palm',palm)]:
        near_parts=None
        for far in [False,True]:
            name=base+('_far' if far else '');K.begin(name,[1,1],120 if far else 800)
            parts=build(far)
            for key,o,role in parts:
                T.apply(o)
                if not far or key.startswith('frond_'):
                    if far:T.fit_bounds(o,next(obj for k,obj,r in near_parts if k==key))
                    # Preserve the leaflets' alternating vertex-paint materials.
                    data=o.data;roles=[m.name for m in data.materials]
                    colours={f.index:K.rgb(COLORS[roles[f.material_index]]) for f in data.polygons}
                    data.materials.clear();data.materials.append(mat)
                    attr=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER');data.color_attributes.active_color=attr;data.color_attributes.render_color_index=0
                    for f in data.polygons:
                        for loop in f.loop_indices:attr.data[loop].color=(*colours[f.index],1)
                        f.material_index=0
                else:
                    source=next(obj for k,obj,r in near_parts if k==key)
                    T.fit_bounds(o,source)
                    if key.startswith('branch_'):T.palette_paint(o,role,mat)
                    else:
                        T.transfer(o,source,mat)
                        # A wide far frond can map to a neighbouring near leaflet.
                        # Keep transferred shading only in the outward hemisphere.
                        normals=[n.vector.copy() for n in o.data.corner_normals]
                        for face in o.data.polygons:
                            for loop in face.loop_indices:
                                if normals[loop].dot(face.normal)<.05:normals[loop]=face.normal.copy()
                        o.data.normals_split_custom_set(normals)
            entries[name]=T.export(name,parts,120 if far else 800);entries[name].update(family='tree',lod='far' if far else 'near',multimesh=True)
            if not far:near_parts=parts
        groups.append({'near':base,'far':base+'_far','switch_distance_m':40,'margin_m':0,'common_aabb':entries[base]['bounds'],'pivot':'trunk base; do not recenter by canopy bounds','far_closed':True})
    manifest={'author':'赵云','virtual_user_id':ACTOR,'revision':'v1','units':'metres, Y up; wind leans toward +X; root at Y=0','palette_srgb':COLORS,'material_contract':{'vertex_color_is_srgb':False,'roughness':.9,'specular':.18,'metallic':0,'opaque':True,'surfaces_per_mesh':1,'textures':False},'assets':entries,'lod_groups':groups,'source':'tools/art/source/coast_plants_435/coast_plants.blend','generator':'tools/art/build_coast_plants_435.py','example_layout_included':False}
    for path in [OUT/'manifest.json',SRC/'asset_stats.json']:path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'coast_plants.blend'),compress=True)
if __name__=='__main__':main()
