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
 'sage':'75976C','sage_light':'94B18A','sage_dark':'587D50',
 'shrub':'7E914E','shrub_light':'A1AC68','shrub_dark':'607A43',
 'cypress':'59755F','cypress_light':'78927A','cypress_dark':'425E4C',
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

def carpet_leaf(name,a,b,width,role):
    a,b=Vector(a),Vector(b);axis=(b-a).normalized();side=Vector((-axis.z,0,axis.x))*width/2;mid=a.lerp(b,.5)
    points=[a,b,mid+side,mid-side,mid+Vector((0,.045,0)),mid-Vector((0,.018,0))]
    return K.mesh(name,points,[(0,2,4),(0,4,3),(0,3,5),(0,5,2),(1,4,2),(1,3,4),(1,5,3),(1,2,5)],role,True)

def carpet_bloom(name,centre,r,phase):
    c=Vector(centre);points=[c+Vector((0,.004,0)),c-Vector((0,.009,0))]
    for i in range(10):
        angle=i*math.tau/10+phase;radius=r*(1 if i%2==0 else .72)
        points.append(c+Vector((radius*math.cos(angle),0,radius*math.sin(angle))))
    faces=[(0,2+i,2+(i+1)%10) for i in range(10)]+[(1,2+(i+1)%10,2+i) for i in range(10)]
    o=K.mesh(name,points,faces,'pink',True);o.data.materials.append(K.MATS['pink_light']);o.data.materials.append(K.MATS['pink_dark'])
    for f in o.data.polygons:f.material_index=(1 if (f.index//2)%3==0 else 0) if f.index<10 else 2
    o['flower_center_blender']=list(K.v(points[0]))
    return o

def iceplant(variant):
    w,d=(1.0,.75) if variant=='a' else (1.4,1.0)
    rim=[]
    for i in range(12):
        theta=i*math.tau/12;c=math.cos(theta);v=math.sin(theta)
        rim.append((math.copysign(abs(c)**.62,c)*w/2,math.copysign(abs(v)**.62,v)*d/2))
    points=[(x,0,z) for x,z in rim]+[(x,.030+.008*(i%3),z) for i,(x,z) in enumerate(rim)]+[(0,.10,0)]
    faces=[tuple(reversed(range(12)))]+[(i,(i+1)%12,(i+1)%12+12,i+12) for i in range(12)]+[(24,12+i,12+(i+1)%12) for i in range(12)]
    o=K.mesh('Ice plant / soft continuous living cushion',points,faces,'ice',True)
    o.data.materials.append(K.MATS['ice_shadow']);o.data.materials.append(K.MATS['ice_light'])
    for f in o.data.polygons:f.material_index=1 if f.normal.z<.15 else (2 if f.index%5==0 else 0)
    count=26 if variant=='a' else 21
    for i in range(count):
        spread=math.sqrt((i+.5)/count);azimuth=i*2.399963
        x=math.cos(azimuth)*w*.43*spread;z=math.sin(azimuth)*d*.43*spread
        theta=i*2.399963+(.3 if variant=='b' else 0);length=.16 if variant=='a' else .22
        c=Vector((x,.105+.008*(i%3),z));u=Vector((math.cos(theta),.08,math.sin(theta)))
        carpet_leaf('Ice plant / dense short leaf %02d'%i,c-u*length*.45,c+u*length*.55,.095 if variant=='a' else .13,['ice','ice_light','ice_shadow'][i%3])
    flowers=[(-.28,-.18),(.0,-.19),(.28,-.15),(-.34,.12),(-.06,.08),(.25,.16),(.04,.27)] if variant=='a' else [(x,z) for z in [-.30,0,.30] for x in [-.45,0,.45]]
    for i,(x,z) in enumerate(flowers):
        carpet_bloom('Ice plant / carpet bloom %02d'%i,(x,.165+.006*(i%3),z),(.09 if variant=='a' else .12)*(1+.06*(i%2)),i*.37)

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

def tetra(name,a,b,r,color):
    a,b=Vector(a),Vector(b);u=(b-a).normalized().cross(Vector((0,0,1))).normalized()*r;v=(b-a).normalized().cross(u).normalized()*r*.4
    return K.mesh(name,[a+u,a-u,b+v,b-v],[(0,1,2),(1,0,3),(1,3,2),(0,2,3)],color,True)

def cypress(far):
    parts=[]
    layers=[((1.65,2.65,0),(4.0,.55,1.40),'cypress_dark'),
            ((2.00,3.60,.04),(3.3,.55,1.25),'cypress'),
            ((2.25,4.55,-.04),(2.6,.50,1.05),'cypress'),
            ((2.40,5.355,0),(1.8,.70,.90),'cypress_light')]
    for i,(at,size,role) in enumerate(layers):
        # Each windward layer is a pair of soft cloud lobes, not a conical skirt.
        for j in range(2):
            x,y,z=at;length,height,depth=size
            centre=(x+(-.21 if j==0 else .21)*length,y+(-.03 if j==0 else .06),z+(-.06 if j==0 else .04))
            dims=(length*(.68 if j==0 else .64),height*(.85 if j==0 else 1.10),depth*(.98 if j==0 else .92))
            rx,ry,rz=[v/2 for v in dims];n=6 if far else 12
            latitudes=[(0,1)] if far else [(-.5,.8660254),(0,1),(.5,.8660254)]
            cx,cy,cz=centre;pts=[(cx,cy-ry,cz)]
            for h,r in latitudes:
                for k in range(n):
                    a=k*math.tau/n;pts.append((cx+rx*r*math.cos(a),cy+ry*h,cz+rz*r*math.sin(a)))
            top=len(pts);pts.append((cx,cy+ry,cz));faces=[(0,1+(k+1)%n,1+k) for k in range(n)]
            for row in range(len(latitudes)-1):
                for k in range(n):
                    a=1+row*n+k;b=1+row*n+(k+1)%n;faces.append((a,b,b+n,a+n))
            last=1+(len(latitudes)-1)*n;faces.extend((last+k,last+(k+1)%n,top) for k in range(n))
            o=K.mesh('Cypress / cloud layer %d soft lobe %d'%(i,j),pts,faces,role,True)
            parts.append(('crown_%d_%d'%(i,j),o,role))
    rings=[((0,0,0),.23,.20),((.30,1.1,-.02),.19,.17),((1.00,2.45,-.03),.15,.13),((1.55,4.1,.03),.105,.085),((2.05,5.35,.02),.045,.04)]
    if far:rings=[rings[0],rings[2],rings[-1]]
    parts.append(('trunk',T.loft('Monterey cypress / stronger wind-bent trunk',rings,3 if far else 8,'wood_dark'),'wood_dark'))
    for i,(a,b) in enumerate([((.75,2.0,-.02),(2.80,2.82,0)),((1.15,2.95,0),(2.70,3.68,.04))]):
        o=tetra('Cypress / windward fork '+str(i),a,b,.12,'wood') if far else K.rod('Cypress / windward fork '+str(i),a,b,.12,'wood',segments=6,top=.04)
        parts.append(('branch_'+str(i),o,'wood'))
    return parts

def palm_frond(index,far):
    angle=index*math.tau/8+.22;u=Vector((math.cos(angle),0,math.sin(angle)));side=Vector((-u.z,0,u.x))
    base=Vector((.65,5.15,0));length=2.35+.15*(index%3);droop=.95+.20*(index%4)
    def centre(t):return base+u*(length*t)+Vector((0,.65*math.sin(math.pi*t)-droop*t*t,0))
    def width(t):return .34*math.sin(math.pi*t)**.75
    if far:
        # Two shoulder stations retain the arch and descending tip at 12 triangles.
        outline=[centre(0),centre(.28)+side*width(.28),centre(.66)+side*width(.66),centre(1),centre(.66)-side*width(.66),centre(.28)-side*width(.28)]
        points=outline+[centre(.45)+Vector((0,.035,0)),centre(.45)-Vector((0,.012,0))]
        faces=[(6,i,(i+1)%6) for i in range(6)]+[(7,(i+1)%6,i) for i in range(6)]
    else:
        samples=[.12,.24,.36,.48,.60,.72,.84,.94];points=[centre(0)]
        for j,t in enumerate(samples):
            c=centre(t);w=width(t)*(1 if j%2 else .92)
            points += [c-side*w,c+Vector((0,.035,0)),c+side*w,c-Vector((0,.012,0))]
        end=len(points);points.append(centre(1));faces=[(0,1+(j+1)%4,1+j) for j in range(4)]
        for row in range(len(samples)-1):
            for j in range(4):
                a=1+row*4+j;b=1+row*4+(j+1)%4;faces.append((a,b,b+4,a+4))
        last=1+(len(samples)-1)*4;faces += [(last+j,last+(j+1)%4,end) for j in range(4)]
    o=K.mesh('Palm / arching drooping frond %02d'%index,points,faces,'palm',True)
    o.data.materials.append(K.MATS['palm_light']);o.data.materials.append(K.MATS['palm_dark'])
    for f in o.data.polygons:
        f.material_index=2 if f.normal.z<0 else (1 if f.center.dot(K.v(side))>base.dot(side) else 0)
    return o

def palm(far):
    parts=[];bands=[.70,1.45,2.20,2.95,3.70,4.45]
    levels=[0,2.6,5.15] if far else [0]+[y for h in bands for y in [h,h+.045]]+[5.15]
    rings=[]
    for y in levels:
        t=y/5.15;r=.11-.05*t;centre=(.65*t**1.25,y,.02*math.sin(t*math.pi))
        rings.append((centre,r,r))
    trunk=T.loft('Palm / slim gently bending ringed trunk',rings,4 if far else 8,'wood')
    trunk.data.materials.append(K.MATS['wood_dark']);trunk.data.materials.append(K.MATS['wood_light'])
    if not far:
        for f in trunk.data.polygons:
            if any(h-.001<f.center.z<h+.046 for h in bands):f.material_index=1
            elif f.index%8==2:f.material_index=2
    parts.append(('trunk',trunk,'wood'))
    for i in range(8):parts.append(('frond_'+str(i),palm_frond(i,far),'palm'))
    hub=tetra('Palm / far growing point',(.65,5.04,0),(.65,5.29,0),.10,'palm_dark') if far else ico('Palm / compact growing point',(.65,5.16,0),(.22,.28,.22),'palm_dark')
    parts.append(('hub',hub,'palm_dark'))
    return parts

def apply_and_paint(o,role,mat):
    T.apply(o);data=o.data;roles=[m.name for m in data.materials]
    face_colors={f.index:K.rgb(COLORS[roles[f.material_index]]) for f in data.polygons}
    data.materials.clear();data.materials.append(mat)
    attr=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER');data.color_attributes.active_color=attr;data.color_attributes.render_color_index=0
    flower_centre=Vector(o['flower_center_blender']) if 'flower_center_blender' in o else None
    for f in data.polygons:
        for loop in f.loop_indices:
            color=face_colors[f.index]
            if flower_centre is not None and (data.vertices[data.loops[loop].vertex_index].co-flower_centre).length<1e-5:color=K.rgb(COLORS['pink_dark'])
            attr.data[loop].color=(*color,1)
        f.material_index=0

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
            if family=='iceplant':entries[name].update(cushion_size_m=[1.0,.75] if variant=='a' else [1.4,1.0],flower_count=7 if variant=='a' else 9,short_leaf_count=26 if variant=='a' else 21,edge_height_range_m=[.030,.046],recommended_pitch_m=[.82,.62] if variant=='a' else [1.18,.84])
    for base,build in [('coast_cypress',cypress),('coast_palm',palm)]:
        near_parts=None
        for far in [False,True]:
            name=base+('_far' if far else '');K.begin(name,[1,1],120 if far else 800)
            parts=build(far)
            for key,o,role in parts:
                T.apply(o)
                if not far or key.startswith('frond_'):
                    if far:
                        T.fit_bounds(o,next(obj for k,obj,r in near_parts if k==key))
                        normals=[n.vector.copy() for n in o.data.corner_normals]
                        for face in o.data.polygons:
                            for loop in face.loop_indices:
                                if normals[loop].dot(face.normal)<.05:normals[loop]=face.normal.copy()
                        o.data.normals_split_custom_set(normals)
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
            if base=='coast_cypress':entries[name].update(cloud_layers=4,layer_lengths_m=[4.32,3.564,2.808,1.944],windward_axis='+X',trunk_crown_offset_x_m=2.05)
            if base=='coast_palm':entries[name].update(frond_count=8,trunk_base_diameter_m=.22,ring_heights_m=[] if far else [.70,1.45,2.20,2.95,3.70,4.45],frond_tip_drop_m=[.95,1.15,1.35,1.55])
            if not far:near_parts=parts
        groups.append({'near':base,'far':base+'_far','switch_distance_m':40,'margin_m':0,'common_aabb':entries[base]['bounds'],'pivot':'trunk base; do not recenter by canopy bounds','far_closed':True})
    manifest={'author':'赵云','virtual_user_id':ACTOR,'revision':'v1.1','units':'metres, Y up; wind leans toward +X; root at Y=0','palette_srgb':COLORS,'material_contract':{'vertex_color_is_srgb':False,'roughness':.9,'specular':.18,'metallic':0,'opaque':True,'surfaces_per_mesh':1,'textures':False},'assets':entries,'lod_groups':groups,'source':'tools/art/source/coast_plants_435/coast_plants.blend','generator':'tools/art/build_coast_plants_435.py','example_layout_included':False}
    for path in [OUT/'manifest.json',SRC/'asset_stats.json']:path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'coast_plants.blend'),compress=True)
if __name__=='__main__':main()
