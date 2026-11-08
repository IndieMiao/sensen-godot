"""Four house-anchor-relative attachments; use flock ~/gs66-render.lock Blender.
No edits to the house, the live farm, navigation or existing kit entries.
"""
from pathlib import Path
import json,math,sys,hashlib
import bpy,bmesh
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/art'))
import build_decor_assets as K
from verify_chef_sign import load_glb,accessor
SRC=ROOT/'tools/art/source/homestead_looks_439';OUT=ROOT/'assets/farm/art'
COLORS=json.loads((SRC/'reference/farm-palette.json').read_text())
ACTOR='8ea32e40-c0ba-4a31-864f-374a6bcbc554'
REC={};PARTS={}

def box(name,at,size,role,bevel=0):return K.box(name,at,size,role,bevel)
def beam(name,a,b,width,role,depth=None):
    a,b=K.v(a),K.v(b);o=box(name,(0,0,0),(width,(b-a).length,depth or width),role)
    o.location=(a+b)/2;o.rotation_mode='QUATERNION';o.rotation_quaternion=(b-a).to_track_quat('Z','Y');return o

def ico(name,at,size,role):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1)
    o=bpy.context.object;o.location=K.v(at);o.scale=(size[0]/2,size[2]/2,size[1]/2)
    return K.finish(o,name,role,True)

def octa(name,at,r,role):
    x,y,z=at;p=[(x-r,y,z),(x+r,y,z),(x,y-r,z),(x,y+r,z),(x,y,z-r),(x,y,z+r)]
    return K.mesh(name,p,[(3,0,4),(3,4,1),(3,1,5),(3,5,0),(2,4,0),(2,1,4),(2,5,1),(2,0,5)],role,True)

def planting(name,x,z,stone=False):
    if stone:
        box(name+' / limestone trough',(x,.12,z),(.29,.24,.30),'stone_light',.018)
        box(name+' / dark soil',(x,.244,z),(.235,.008,.245),'soil_dark')
    else:
        K.lathe(name+' / terracotta pot',[(.075,0),(.12,.18),(.125,.20)],'orange',segments=8,at=(x,0,z))
        K.cylinder(name+' / pot soil',(x,.204,z),.109,.008,'soil_dark',segments=8)
    floor=.25 if stone else .21
    for i,(dx,dz,h) in enumerate([(-.07,-.02,.10),(.06,-.04,.11),(0,.06,.12)]):
        ico(name+' / foliage '+str(i),(x+dx,floor+h*.55,z+dz),(.19,h*1.6,.16),'leaf_light' if i==1 else 'leaf')
    for i,(dx,dz) in enumerate([(-.07,.02),(.035,-.035),(.06,.065)]):octa(name+' / cream bloom '+str(i),(x+dx,floor+.14,z+dz),.026,'flower')

def pitched_roof(name,cx,z0,z1,half,eave,peak,rows=4,cols=4):
    rise=peak-eave;length=math.hypot(half,rise);slope=math.atan2(rise,half);depth=z1-z0
    for side in [-1,1]:
        o=box(name+' / roof slab',(cx+side*half/2,(eave+peak)/2,(z0+z1)/2),(length,.065,depth),'orange');o.rotation_euler.y=side*slope
        for row in range(rows):
            t=(row+.5)/rows
            for col in range(cols):
                z=z0+(col+.5)*depth/cols;x=cx+side*half*t;y=peak-rise*t+.050
                role='orange_light' if (row*7+col)%4==0 else 'orange'
                o=box(name+' / clay tile %d %d %d'%(side,row,col),(x,y,z),(length/rows+.009,.025,depth/cols-.006),role);o.rotation_euler.y=side*slope
        for z in [z0,z1]:beam(name+' / orange verge',(cx,peak+.035,z),(cx+side*half,eave+.025,z),.060,'orange')
    beam(name+' / ridge cap',(cx,peak+.065,z0-.025),(cx,peak+.065,z1+.025),.075,'orange')

def lean_roof(name,x0,x1,z0,z1,low,high):
    run=x1-x0;rise=high-low;length=math.hypot(run,rise);slope=math.atan2(rise,run);depth=z1-z0
    o=box(name+' / roof slab',((x0+x1)/2,(low+high)/2,(z0+z1)/2),(length,.060,depth),'orange');o.rotation_euler.y=-slope
    for row in range(5):
        t=(row+.5)/5
        for col in range(6):
            role='orange_light' if (row*7+col)%4==0 else 'orange'
            o=box(name+' / clay tile %d %d'%(row,col),(x0+run*t,low+rise*t+.044,z0+(col+.5)*depth/6),(length/5+.009,.024,depth/6-.006),role);o.rotation_euler.y=-slope
    for z in [z0,z1]:beam(name+' / roof verge',(x0,low+.02,z),(x1,high+.02,z),.055,'orange')
    beam(name+' / outer eave',(x0,low+.02,z0),(x0,low+.02,z1),.055,'orange')

def porch_a():
    # Only flat paving and the >=2m cantilever extend into reserved row 14.
    for i in range(8):box('Timber porch / ground plank '+str(i),(-.82+(i+.5)*1.64/8,.0175,1.48),(1.64/8-.005,.035,.88),'wood_light' if i%3==0 else 'wood')
    for x in [-1.20,1.20]:
        box('Timber porch / rear post',(x,1.04,.45),(.085,2.08,.06),'wood')
        box('Timber porch / post foot',(x,.065,.45),(.12,.13,.06),'wood_dark')
        box('Timber porch / post capital',(x,2.065,.45),(.14,.10,.06),'wood_light')
        beam('Timber porch / rear diagonal bracket',(x,1.72,.45),(x-math.copysign(.24,x),2.05,.45),.065,'wood_light')
        box('Timber porch / cantilever beam',(x,2.082,.95),(.075,.105,1.02),'wood')
    pitched_roof('Timber porch',0,.86,1.45,1.28,2.09,2.31,rows=5,cols=3)
    # Front-facing side bench, wholly behind z=.975 and outside the old wall.
    box('Timber porch / bench seat',(1.17,.30,.73),(.56,.055,.26),'wood_light')
    for x in [.96,1.38]:
        for z in [.645,.815]:box('Timber porch / bench leg',(x,.135,z),(.045,.27,.045),'wood')
    box('Timber porch / bench back',(1.17,.43,.59),(.56,.19,.055),'wood_light')
    box('Timber porch / bench stretcher',(1.17,.12,.73),(.40,.04,.20),'wood')
    planting('Timber porch / left plant',-1.09,.63)
    planting('Timber porch / right plant',1.49,.40)
    # A modelled amber door lantern, no runtime Light node.
    box('Timber porch / lamp backplate',(-.76,1.10,.883),(.105,.18,.028),'wood_dark')
    box('Timber porch / lamp amber panes',(-.76,1.10,.925),(.072,.12,.065),'yellow')
    for y in [1.023,1.177]:box('Timber porch / lamp metal cap',(-.76,y,.925),(.105,.028,.080),'wood_dark')
    return {'stage':'porch','look':'a','placement':'house anchor, no additional transform','porch_reference_z':1.48,'floor_top_m':.035,'front_eave_min_m':2.0,'ground_fixture_z_max':.975}

def arch_block(name,points,depth,z,role):
    verts=[(x,y,z-d/2) for d in [depth] for x,y in points]+[(x,y,z+depth/2) for x,y in points]
    n=len(points);faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return K.mesh(name,verts,faces,role)

def porch_b():
    for row in range(3):
        for col in range(4):
            box('Stone porch / flush paving %d %d'%(row,col),(-.82+(col+.5)*1.64/4,.018, 1.03+(row+.5)*.90/3),(1.64/4-.004,.036,.90/3-.004),'stone_light' if (row+col)%3 else 'stone')
    cx=-.35;inner=.31;outer=.41;sill=.88
    for side in [-1,1]:
        box('Stone porch / arch foot',(cx+side*.36,.020,.919),(.12,.040,.085),'stone')
        for row in range(4):box('Stone porch / jamb course',(cx+side*.36,.04+(row+.5)*.84/4,.919),(.10,.84/4-.004,.075),'stone_light' if row%2 else 'stone')
    for i in range(9):
        a=i*math.pi/9+.007;b=(i+1)*math.pi/9-.007
        pts=[(cx+inner*math.cos(a),sill+inner*math.sin(a)),(cx+outer*math.cos(a),sill+outer*math.sin(a)),(cx+outer*math.cos(b),sill+outer*math.sin(b)),(cx+inner*math.cos(b),sill+inner*math.sin(b))]
        arch_block('Stone porch / arch voussoir '+str(i),pts,.075,.919,'stone_light' if i%3 else 'stone')
    planting('Stone porch / left trough',-1.09,.65,True)
    planting('Stone porch / right trough',1.10,.65,True)
    return {'stage':'porch','look':'b','placement':'house anchor, no additional transform','porch_reference_z':1.48,'floor_top_m':.036,'arch_attached_to_existing_door':True,'ground_fixture_z_max':.975}

def wing_body(name,stone):
    # Rear wall stops short of the widest rotated Lv3 stone fence; roof may overhang above it.
    x0=-2.30;x1=-.845;z0=-1.34;z1=-.05;low=.98;high=1.27
    pts=[(x0,.04,z0),(x1,.04,z0),(x1,.04,z1),(x0,.04,z1),(x0,low,z0),(x1,high,z0),(x1,high,z1),(x0,low,z1)]
    K.mesh(name+' / attached room',pts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'stone_light' if stone else 'plaster')
    box(name+' / foundation',((x0+x1)/2,.045,(z0+z1)/2),(x1-x0+.03,.09,z1-z0+.03),'stone',.014)
    lean_roof(name,-2.37,-.82,-1.51,.01,1.035,1.355)

def window(name,x,y,z):
    box(name+' / green frame',(x,y,z),(.48,.41,.045),'green')
    box(name+' / glass',(x,y,z+.028),(.365,.30,.016),'glass')
    box(name+' / vertical muntin',(x,y,z+.042),(.022,.30,.014),'cream')
    box(name+' / horizontal muntin',(x,y,z+.043),(.365,.021,.014),'cream')
    box(name+' / sill',(x,y-.215,z+.025),(.53,.045,.14),'wood_light')
    for side in [-1,1]:
        box(name+' / shutter',(x+side*.28,y,z+.02),(.10,.36,.025),'green')
        for k in range(3):box(name+' / shutter louvre',(x+side*.28,y-.105+k*.105,z+.038),(.08,.018,.014),'green_light')

def secondary_window(name,center,yaw):
    # Five closed boxes: 60 triangles; the exposed side/rear retain a readable green frame.
    before=set(K.CURRENT.objects)
    box(name+' / green surround',(0,0,0),(.46,.37,.045),'green')
    box(name+' / blue glass',(0,0,.028),(.35,.27,.016),'glass')
    box(name+' / upright muntin',(0,0,.042),(.022,.27,.014),'cream')
    box(name+' / horizontal muntin',(0,0,.043),(.35,.021,.014),'cream')
    box(name+' / sill',(0,-.202,.025),(.51,.035,.11),'wood_light')
    transform=Matrix.Translation(K.v(center))@Matrix.Rotation(math.radians(yaw),4,'Z')
    bpy.context.view_layer.update()
    for obj in set(K.CURRENT.objects)-before:obj.matrix_world=transform@obj.matrix_world

def secondary_facades(name):
    secondary_window(name+' / outer side window',(-2.345,.64,-.60),-90)
    secondary_window(name+' / rear window',(-1.40,.69,-1.347),180)

def chimney(name,x,z,bottom,top,stone):
    width=.36 if stone else .22;depth=.35 if stone else .23
    if stone:
        box(name+' / continuous chimney core',(x,(bottom+top)/2,z),(width*.91,top-bottom,depth*.91),'stone')
        for i in range(6):
            h=(top-bottom)/6;y=bottom+(i+.5)*h
            # A simple clipped stone prism, 20 triangles per course.
            r=.035;outline=[(-width/2,-depth/2+r),(-width/2+r,-depth/2),(width/2,-depth/2),(width/2,depth/2-r),(width/2-r,depth/2),(-width/2,depth/2)]
            pts=[(x+a,y+dy,z+b) for dy in [-h/2+.002,h/2-.002] for a,b in outline]
            K.mesh(name+' / limestone chimney course '+str(i),pts,[tuple(reversed(range(6))),tuple(range(6,12))]+[(j,(j+1)%6,(j+1)%6+6,j+6) for j in range(6)],'stone_light' if i%2 else 'stone',True)
    else:
        box(name+' / small chimney body',(x,(bottom+top)/2,z),(width,top-bottom,depth),'stone')
        for y in [top-.30,top-.18,top-.06]:box(name+' / chimney seam',(x,y,z+depth/2+.001),(width*.94,.012,.008),'stone_light')
    lip=.045;outer_w=width+.085;outer_d=depth+.085
    for dx in [-1,1]:box(name+' / chimney side lip',(x+dx*(outer_w/2-lip/2),top+.035,z),(lip,.07,outer_d),'stone_light')
    for dz in [-1,1]:box(name+' / chimney cross lip',(x,top+.035,z+dz*(outer_d/2-lip/2)),(outer_w-2*lip,.07,lip),'stone_light')
    box(name+' / dark chimney opening',(x,top+.003,z),(outer_w-2*lip,.006,outer_d-2*lip),'roof_dark')
    return [x,top+.075,z]

def kitchen_wing_a():
    name='Timber kitchen';wing_body(name,False);secondary_facades(name)
    for x in [-2.285,-.87]:box(name+' / front timber corner',(x,.51,-.015),(.055,.96,.07),'wood')
    box(name+' / front timber sill',(-1.58,.18,-.012),(1.39,.065,.065),'wood_light')
    window(name,-1.60,.63,-.018)
    # Herb box sits directly under the new window.
    for x in [-1.98,-1.22]:box(name+' / herb box end',(x,.245,.10),(.045,.18,.24),'wood')
    for z in [-.02,.22]:box(name+' / herb box side',(-1.60,.245,z),(.80,.18,.035),'wood_light')
    box(name+' / herb box bottom',(-1.60,.17,.10),(.80,.035,.24),'wood')
    box(name+' / herb soil',(-1.60,.321,.10),(.71,.008,.19),'soil_dark')
    for i in range(5):ico(name+' / herbs '+str(i),(-1.88+i*.14,.415,.10+(.025 if i%2 else -.025)),(.18,.23,.16),'leaf' if i%2 else 'leaf_light')
    smoke=chimney(name,-2.02,-1.05,1.12,1.74,False)
    return {'stage':'kitchen_extension','look':'a','placement':'house anchor, no additional transform','reference_centre':[-1.63,0,-.75],'smoke_anchor':smoke,'house_join_x':-.845,'required_scenery_moves':['bench','left_house_bush']}

def kitchen_wing_b():
    name='Stone kitchen';wing_body(name,True);secondary_facades(name)
    # Slightly irregular visible courses rather than high-poly boulders.
    for row in range(3):
        for col in range(4):
            if row==1 and col in [1,2]:continue # front window opening in the cladding
            x=-2.28+(col+.5)*1.38/4;y=.16+row*.285
            box(name+' / front stone %d %d'%(row,col),(x,y,-.014),(.325,.25,.065),'stone_light' if (row+col)%3 else 'stone',.012)
    for row in range(3):
        for col in range(3):
            box(name+' / outer side stone %d %d'%(row,col),(-2.315,.16+row*.285,-1.38+(col+.5)*1.30/3),(.045,.25,.40),'stone_light' if (row+col)%3 else 'stone')
    window(name,-1.60,.63,.035)
    smoke=chimney(name,-2.03,-1.06,.07,2.29,True)
    return {'stage':'kitchen_extension','look':'b','placement':'house anchor, no additional transform','reference_centre':[-1.63,0,-.75],'smoke_anchor':smoke,'house_join_x':-.845,'required_scenery_moves':['bench','left_house_bush']}

def export(name,meta):
    bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT');deps=bpy.context.evaluated_depsgraph_get();copies=[];parts=[]
    for source in K.CURRENT.objects:
        data=bpy.data.meshes.new_from_object(source.evaluated_get(deps),depsgraph=deps)
        o=bpy.data.objects.new(source.name+' export',data);bpy.context.scene.collection.objects.link(o);o.matrix_world=source.matrix_world.copy();o.select_set(True);copies.append(o)
        pts=[source.matrix_world@v.co for v in data.vertices]
        pts=[(v.x,v.z,-v.y) for v in pts]
        parts.append({'name':source.name,'bounds':[[min(v[k] for v in pts) for k in range(3)],[max(v[k] for v in pts) for k in range(3)]]})
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();o=bpy.context.object;o.name=name
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    data=o.data;data.name=name+'_mobile'
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free();data.update();data.calc_loop_triangles()
    count=len(data.loop_triangles);assert count<=1500,(name,count)
    points=[p.co.copy() for p in data.vertices];faces=[list(p.vertices) for p in data.polygons];offset=len(points)
    points.extend(HOUSE_POINTS);faces.extend([[offset+int(i) for i in tri] for tri in HOUSE_FACES])
    tree=BVHTree.FromPolygons(points,faces,all_triangles=True)
    attr=data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER');data.color_attributes.active_color=attr;data.color_attributes.render_color_index=0
    ao={}
    for face in data.polygons:
        color=data.materials[face.material_index].diffuse_color[:3]
        for index in face.loop_indices:
            loop=data.loops[index];n=data.corner_normals[index].vector.normalized();key=(loop.vertex_index,tuple(round(v,2) for v in n))
            if key not in ao:
                tangent=n.cross(Vector((0,0,1)))
                if tangent.length<.01:tangent=n.cross(Vector((1,0,0)))
                tangent.normalize();bt=n.cross(tangent);hits=0
                for ray in range(8):
                    angle=ray*2.399;r=math.sqrt((ray+.5)/8)*.88
                    direction=(n*math.sqrt(1-r*r)+tangent*(math.cos(angle)*r)+bt*(math.sin(angle)*r)).normalized()
                    hit=tree.ray_cast(data.vertices[loop.vertex_index].co+n*.008,direction,.38)
                    if hit[0] is not None:hits+=1-hit[3]/.38
                ao[key]=1-.38*hits/8
            attr.data[index].color=(*(v*ao[key] for v in color),1)
    data.materials.clear();data.materials.append(EXPORT_MAT)
    for f in data.polygons:f.material_index=0
    for uv in list(data.uv_layers):data.uv_layers.remove(uv)
    path=OUT/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_texcoords=False,export_tangents=False,export_animations=False,export_cameras=False,export_lights=False,export_extras=False)
    d,b=load_glb(path);p=d['meshes'][0]['primitives'][0];xyz=accessor(d,b,p['attributes']['POSITION']);bounds=[[min(v[k] for v in xyz) for k in range(3)],[max(v[k] for v in xyz) for k in range(3)]]
    assert len(d['meshes'])==1 and len(d['meshes'][0]['primitives'])==1
    entry={'file':name+'.glb','triangles':count,'surfaces':1,'bounds':bounds,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'origin':'P0Garden.ANCHORS.house','axes':'metres, Y up, +Z toward camera','author':'赵云','virtual_user_id':ACTOR,'source':'tools/art/source/homestead_looks_439/homestead_looks.blend',**meta}
    bpy.data.objects.remove(o,do_unlink=True);bpy.data.meshes.remove(data)
    REC[name]=entry;PARTS[name]=parts;print('HOMESTEAD_439',name,count,bounds,flush=True)

def main():
    global EXPORT_MAT,HOUSE_POINTS,HOUSE_FACES
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
    for role,value in COLORS.items():
        m=bpy.data.materials.new(role);m.diffuse_color=(*K.rgb(value),1);m.use_nodes=True
        p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=m.diffuse_color;p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18;K.MATS[role]=m
    EXPORT_MAT=bpy.data.materials.new('Homestead attachments / farm vertex paint');EXPORT_MAT.use_nodes=True;EXPORT_MAT.use_backface_culling=True
    p=EXPORT_MAT.node_tree.nodes['Principled BSDF'];p.inputs['Roughness'].default_value=.9;p.inputs['Specular IOR Level'].default_value=.18
    vc=EXPORT_MAT.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';EXPORT_MAT.node_tree.links.new(vc.outputs['Color'],p.inputs['Base Color'])
    doc,buf=load_glb(OUT/'house_cottage.glb');pr=doc['meshes'][0]['primitives'][0]
    HOUSE_POINTS=[K.v(p) for p in accessor(doc,buf,pr['attributes']['POSITION'])];ids=[x[0] for x in accessor(doc,buf,pr['indices'])];HOUSE_FACES=[ids[i:i+3] for i in range(0,len(ids),3)]
    for name,make in [('porch_a',porch_a),('porch_b',porch_b),('kitchen_wing_a',kitchen_wing_a),('kitchen_wing_b',kitchen_wing_b)]:
        K.begin(name,[1,1],1500);meta=make();export(name,meta)
    spec={'author':'赵云','virtual_user_id':ACTOR,'revision':'v1.1','house_sha256':hashlib.sha256((OUT/'house_cottage.glb').read_bytes()).hexdigest(),'runtime_reference':'8493a5c4','palette_srgb':COLORS,'assets':REC,'components':PARTS,'protected_cells':[[x,14] for x in [4,5,7,8,9,10,11]],'porch_floor_max_m':.05,'front_eave_clearance_m':2.0,'ground_fixture_front_limit_z':.975,'source':'tools/art/source/homestead_looks_439/homestead_looks.blend','generator':'tools/art/build_homestead_looks_439.py'}
    (SRC/'asset_stats.json').write_text(json.dumps(spec,ensure_ascii=False,indent=2)+'\n')
    (OUT/'homestead_looks_manifest.json').write_text(json.dumps({k:v for k,v in spec.items() if k!='components'},ensure_ascii=False,indent=2)+'\n')
    manifest=json.loads((OUT/'manifest.json').read_text());manifest['assets'].update(REC);(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    bpy.context.scene.unit_settings.system='METRIC';bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'homestead_looks.blend'),compress=True)
if __name__=='__main__':main()
