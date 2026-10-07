"""Courtyard R2: recognizable posed cats, full orange crowns and a longer meadow path."""
import math,random,json,importlib.util
from pathlib import Path
import kit as k
import series_revision as r
from kit import begin,cube,cylinder,tube,ellipsoid,mesh

def solid(o):
    o['atlas_constant_colour']=True
    return o

def smooth_path(points):
    from mathutils import Vector
    p=[Vector(points[0])]+[Vector(v) for v in points]+[Vector(points[-1])]
    out=[]
    for i in range(1,len(p)-2):
        a,b,c,d=p[i-1:i+3]
        for j in range(7):
            t=j/7;out.append(tuple(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)))
    return out+[tuple(points[-1])]

def cat(pose,tone):
    lying=pose in ('sleep','loaf');sitting=pose=='sit'
    body_y=.19 if lying else .29 if sitting else .32
    width,height,length=(.43,.29,.67) if lying else (.39,.50,.40) if sitting else (.36,.32,.62)
    solid(ellipsoid('Rounded feline ribcage',(0,body_y,0),(width,height,length),tone,20,10))
    hy=.235 if lying else .52 if sitting else .46;hz=.28 if not sitting else .14
    solid(ellipsoid('Broad round feline face',(0,hy,hz),(.43,.36,.37),tone,20,12))
    for x in (-.125,.125):
        solid(mesh('Wide triangular feline ear',[(x-.076,hy+.11,hz-.02),(x+.074,hy+.11,hz-.02),(x,hy+.295,hz-.012),(x-.055,hy+.12,hz+.074),(x+.055,hy+.12,hz+.074),(x,hy+.266,hz+.070)],[(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)],tone,smooth=True))
        solid(mesh('Pink inner ear',[(x-.043,hy+.141,hz+.075),(x+.039,hy+.141,hz+.075),(x,hy+.235,hz+.074)],[(0,1,2)],'DA9495'))
    for x in (-.100,.100):
        # Facial features follow the curved head rather than floating at its frontmost tip.
        solid(ellipsoid('Large dark feline eye',(x,hy+.035,hz+.158),(.064,.077,.028),'27332E',12,6))
        solid(ellipsoid('Eye catchlight',(x-.010,hy+.051,hz+.174),(.018,.021,.008),'FFF8E6',8,4))
        solid(ellipsoid('Cream rounded muzzle',(x*.46,hy-.045,hz+.173),(.12,.080,.053),'F8E9CD',12,6))
    solid(ellipsoid('Small pink nose',(0,hy-.011,hz+.205),(.048,.033,.025),'C6777C',10,5))
    for side in (-1,1):
        solid(tube('Tiny smile',[(0,hy-.041,hz+.204),(side*.024,hy-.063,hz+.194),(side*.041,hy-.055,hz+.19)],.0038,'775849',5))
    for x in (-.125,.125):
        for z in ((-.19,.24) if not sitting else (-.10,.23)):
            if lying:solid(ellipsoid('Tucked cream feline paw',(x,.061,z),(.15,.115,.23),'F6E9D2',12,6))
            elif sitting:
                if z>0:solid(ellipsoid('Seated straight foreleg',(x,.18,z),(.11,.35,.12),'F6E9D2',12,6))
                solid(ellipsoid('Seated feline paw',(x,.05,z),(.16,.10,.19),'F6E9D2',12,6))
            else:
                solid(ellipsoid('Distinct standing leg',(x,.14,z),(.11,.28,.12),tone,12,6))
                solid(ellipsoid('White standing foot',(x,.045,z+.016),(.13,.09,.17),'F6E9D2',12,6))
    if sitting:solid(ellipsoid('White feline chest',(0,.30,.178),(.22,.33,.075),'F0EBDF',16,8))
    tail=[(0,body_y,-.28),(.23,.14,-.39),(.33,.12,-.22),(.32,.16,.02)] if lying else [(0,.25,-.23),(.22,.13,-.28),(.31,.10,-.10),(.25,.08,.18)] if sitting else [(0,.37,-.28),(.07,.60,-.38),(.08,.76,-.34),(.025,.82,-.25)]
    solid(tube('Soft curved feline tail',smooth_path(tail),.037,tone,8))
    if pose=='walk':
        for x,y,z,size,c in [(-.115,.411,-.14,(.15,.09,.23),'C78649'),(.095,.438,.02,(.16,.07,.20),'656A66'),(-.10,hy+.118,hz+.035,(.15,.10,.17),'C78649')]:solid(ellipsoid('Calico colour patch',(x,y,z),size,c,12,6))
    else:
        # Thin stripes sit on the fur, not raised baguette scoring.
        for z in (-.18,-.055,.08):
            pts=[]
            for i in range(9):
                x=-width*.41+i*width*.82/8
                y=body_y+height/2*math.sqrt(max(.025,1-(x/(width/2))**2-(z/(length/2))**2))+.001
                pts.append((x,y,z))
            solid(tube('Flush tabby stripe',pts,.0045,'B87539' if tone=='D9A558' else '6F7880',5))

def orchard_tree():
    src=k.ROOT/'assets/rooms/_shared/plants/source/build_plants.py'
    spec=importlib.util.spec_from_file_location('shared_leaf_shapes',src);lib=importlib.util.module_from_spec(spec);spec.loader.exec_module(lib)
    tube('Rounded orange tree trunk',[(0,.03,0),(-.045,.8,.03),(.04,1.42,0),(0,2.42,0)],.072,'94653F',8)
    rng=random.Random(1812)
    for ci in range(13):
        a=ci*2.399;rad=.43 if ci<9 else .23
        center=(math.cos(a)*rad,2.20+(ci%4)*.22,math.sin(a)*rad)
        tube('Fruit tree fork',[(0,1.5,0),(center[0]*.7,center[1]-.2,center[2]*.7),center],.025,'94653F',6)
        for j in range(40):
            a=j*2.399+ci;rad=.08+.24*math.sqrt(rng.random());yy=rng.uniform(-.16,.17)
            start=(center[0]+math.cos(a)*rad,center[1]+yy,center[2]+math.sin(a)*rad)
            end=(start[0]+math.cos(a)*.20,start[1]+.06,start[2]+math.sin(a)*.20)
            solid(lib.blade('Dense orange canopy leaf',start,end,.11,lib.GREENS[(j+ci)%6],seed=j+ci))
    for x,y,z in [(-.54,2.21,.34),(.39,2.61,.49),(.56,2.00,.09),(-.18,2.74,-.45),(.09,2.25,.69),(-.56,2.48,-.09)]:
        solid(ellipsoid('Ripe true-orange fruit',(x,y,z),(.25,.26,.25),'F0781C',12,6))
        solid(lib.blade('Orange fruit stem leaf',(x,y+.12,z),(x+.10,y+.18,z),.07,lib.GREENS[2]))

def revise():
    # Orient all four faces toward review space, while keeping distinct poses.
    for name,yaw in [('counter_cat',25),('sleeping_cat',20),('calico_cat',5),('seated_cat',35)]:
        rec=k.KITS[name];rec['yaw']=yaw;rec['root'].rotation_euler.z=math.radians(yaw)
    r.move('sleeping_cat',(-.03,-.008,2.75));r.move('seated_cat',(-.60,.065,1.60))
    begin('courtyard_orange_tree',at=(-2.35,.06,-1.75));orchard_tree()
    k.instance('courtyard_orange_tree','courtyard_orange_tree_right',(2.38,.06,-1.75),73)
    # Larger meadow keeps the fixed courtyard floor and furniture unchanged.
    r.clear('grass_base');cube('Extended rounded meadow',(0,0,0),(10,.16,10.8),'799C4E',.18,'plaster')
    # Keep the same authored procedural meadow material after clearing the old mesh.
    from importlib.util import spec_from_file_location,module_from_spec
    spec=spec_from_file_location('courtyard_meadow',Path(__file__).with_name('revision.py'));mod=module_from_spec(spec);spec.loader.exec_module(mod)
    mod.meadow_material()
    r.move('grass_base',(0,-.30,.80))
    rng=random.Random(1813)
    for i in range(110):
        x=rng.uniform(-4.82,4.82);z=rng.uniform(-4.42,6.05)
        if abs(x)<3.25 and -2.95<z<3.25:continue
        k.instance('grass_clump','r2_meadow_tuft_%03d'%i,(x,-.21,z),rng.uniform(0,360))
    begin('meadow_pebbles')
    for i in range(20):
        x=rng.uniform(-4.6,4.6);z=rng.uniform(3.25,5.9)
        solid(ellipsoid('Small meadow pebble',(x,-.198,z),(.075+rng.random()*.055,.043,.065),'CABC94',7,4))
    r.clear('garden_stepping_stones')
    for j in range(10):
        x=math.sin(j*.62)*.36+(-.17 if j%2 else .17);z=.14+j*.247
        o=cube('Visible winding stepping stone',(x,-.045,z),(.48+rng.uniform(-.05,.05),.12,.33+rng.uniform(-.025,.025)),'E7CEAE',.065);o.rotation_euler.z=math.sin(j*.9)*.19
    # Orange checked woven mat, with broad crossing stripes.
    k.CURRENT=k.KITS['entry_step']
    for o in list(k.CURRENT['objects']):
        if 'Mat fine' in o.name:k.CURRENT['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
    r.recolor('entry_step','D98C3C',lambda o:'mat' in o.name.lower())
    for i in range(9):cube('Cream checked mat warp',(-.49+i*.1225,.161,0),(.020,.004,.42),'F9D69C',0)
    for z in (-.13,0,.13):cube('Cream checked mat weft',(0,.163,z),(1.05,.004,.020),'F9D69C',0)
    # Two transparent bean jars with beans filling their actual volume.
    r.clear('cookie_jars')
    for x in (-.17,.17):
        cylinder('Coffee jar base',(x,.025,0),.114,.03,'B4936B',vertices=16)
        cylinder('Coffee jar copper lid',(x,.36,0),.12,.037,'A37349',vertices=16)
        for j in range(40):
            a=j*2.399;rr=.077*math.sqrt((j%7+1)/7);y=.054+(j//8)*.054
            o=solid(ellipsoid('Visible roasted coffee bean',(x+math.cos(a)*rr,y,math.sin(a)*rr),(.065,.039,.042),['9E623D','BE7E41','82502E'][j%3],8,4));o.rotation_euler.z=a
    r.move('cookie_jars',(.87,1.82,-2.32))
    k.CURRENT=k.KITS['cookie_jars'];cube('Small coffee bean jar ledge',(0,-.028,-.10),(.73,.055,.60),'B98D5B',.014,'wood')
    begin('coffee_jar_glass',at=(.87,1.82,-2.32))
    for x in (-.17,.17):k.lathe('Clear glass bean jar',(x,.04,0),[(0,.111),(.29,.111),(.30,.099)],'E3EBE0',20)
    for name in ('back_wall','left_door_wall'):
        r.recolor(name,'C9AE8A',lambda o:'backing' in o.name.lower() or 'flanking' in o.name.lower())
        for o in k.KITS[name]['objects']:
            if 'sandstone' in o.name.lower():o.data.materials.clear();o.data.materials.append(k.material(rng.choice(['E3C299','EAD0A7','D9B890','E8C79E'])))
    r.sync_instances()

def manifest(d):
    d['revision']='R2';d['shared_plants']=[p for p in d['shared_plants'] if not p['name'].startswith('FruitTree')]
    d['botanical_assets']=['courtyard_orange_tree'];d['material_overrides']['coffee_jar_glass']={'alpha':.12}
    d['boundaries']=[{'name':'meadow_floor','at':[0,-.32,.80],'size':[10,.20,10.8]}, {'name':'meadow_front_limit','at':[0,.55,6.20],'size':[10.2,1.8,.12]}, {'name':'meadow_back_limit','at':[0,.55,-4.60],'size':[10.2,1.8,.12]}, {'name':'meadow_left_limit','at':[-5.02,.55,.80],'size':[.12,1.8,10.9]}, {'name':'meadow_right_limit','at':[5.02,.55,.80],'size':[.12,1.8,10.9]}]
    from liubei_r2 import fit_camera
    fit_camera(d,(2048,2048),[(152.32,1272.32),(1130.24,1815.04),(1932.8,1310.72)])

    d['review_views']=[]
    for name,pos in [('orange-counter',[1.32,1.50,-.90]),('standing-calico',[-.38,.40,-.05]),('seated-gray',[-.60,.42,1.60]),('entry-gray',[-.03,.21,2.75])]:
        d['review_views'].append({'name':'cat-'+name,'target':pos,'position':[pos[0]+2,pos[1]+1.4,pos[2]+3],'size':1.30})
    d['review_views'][1]['position']=[.2,1.0,.65]
