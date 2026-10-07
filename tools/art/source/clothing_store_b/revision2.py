"""Boutique R2: scalloped flower lamp, readable jewelry and distinct apparel."""
import math,json
import kit as k
import boutique as b
import series_revision as r
from kit import begin,cube,cylinder,tube,ellipsoid,mesh

def solid(o):o['atlas_constant_colour']=True;return o

def petal_lamp():
    r.clear('petal_pendant');tube('Brass suspension stem',[(0,0,0),(0,-.34,0)],.018,'brass',8)
    cylinder('Flower neck cap',(0,-.34,0),.093,.065,'D7AD54',vertices=24)
    for layer,(n,radius,drop) in enumerate([(8,.44,.32),(8,.37,.29),(7,.28,.23)]):
        for j in range(n):
            a=j*math.tau/n+layer*.29;vs=[];faces=[];steps=8;across=8
            for side in (0,1):
                for row in range(steps+1):
                    t=row/steps
                    for col in range(across+1):
                        u=-1+2*col/across
                        rr=.064+(radius-.064)*math.sin(t*math.pi/2)*(1-.10*u*u)
                        ang=a+u*math.pi/n*(.68+.35*t)
                        yy=-.35-layer*.105-drop*t+.055*u*u*t*t
                        vs.append((math.sin(ang)*rr,yy+side*.012,math.cos(ang)*rr))
            count=(steps+1)*(across+1)
            for side in (0,1):
                for row in range(steps):
                    for col in range(across):
                        q=side*count+row*(across+1)+col;f=(q,q+1,q+across+2,q+across+1);faces.append(f if side==0 else tuple(reversed(f)))
            # Thin shell edge follows the scalloped petal perimeter.
            edge=list(range(across+1))+[row*(across+1)+across for row in range(1,steps+1)]+[steps*(across+1)+col for col in range(across-1,-1,-1)]+[row*(across+1) for row in range(steps-1,0,-1)]
            for q,nextq in zip(edge,edge[1:]+edge[:1]):faces.append((q,nextq,nextq+count,q+count))
            o=mesh('Curved scalloped petal layer '+str(layer),vs,faces,['E5D4AF','EFE0BB','F3E4C4'][layer],smooth=True);solid(o)
    begin('flower_pendant_glow',at=k.KITS['petal_pendant']['at'])
    ellipsoid('Warm recessed flower diffuser',(0,-.75,0),(.25,.06,.25),'FFEBC0',20,8)

def necklace_bust(x,y,z,pearls=False):
    points=[(-.135,0),(-.185,.07),(-.175,.24),(-.060,.34),(-.060,.405),(.060,.405),(.060,.34),(.175,.24),(.185,.07),(.135,0)]
    o=b.extruded('Shouldered necklace display bust',points,.11,'E4D6C2' if pearls else 'D7A346',.018,'matte');o.location=k.v((x,y,z))
    cylinder('Necklace display oval base',(x,y+.013,z),.145,.026,'E5C183',vertices=20)
    pts=[]
    for j in range(21):
        a=math.pi+j*math.pi/20;pts.append((x+math.cos(a)*.135,y+.295+math.sin(a)*.14,z+.073))
    tube('Gold necklace chain',pts,.008,'C99035',6)
    for j,p in enumerate(pts):
        if pearls or j%2==0:solid(ellipsoid('Ivory necklace pearl' if pearls else 'Gold necklace bead',p,(.031,.031,.024) if pearls else (.022,.025,.018),'F8F0DD' if pearls else 'DCA948',10,6))
    solid(ellipsoid('Heart necklace pendant',(x,y+.143,z+.080),(.050,.054,.017),'DCA948',10,6))

def earrings(x,y,z,tone):
    cube('Earring stand velvet foot',(x,y+.018,z),(.25,.036,.15),'D998AC',.018)
    tube('Earring T upright',[(x,y+.03,z),(x,y+.32,z)],.012,'D1A045',6)
    tube('Earring T crossarm',[(x-.095,y+.32,z),(x+.095,y+.32,z)],.012,'D1A045',6)
    for dx in (-.083,.083):
        b.ring('Suspended gold earring',(x+dx,y+.255,z+.014),.031,.048,'D1A045',.006)
        solid(ellipsoid('Earring teardrop stone',(x+dx,y+.205,z+.021),(.036,.061,.017),tone,10,6))

def glasses(x,y,z,tone):
    cube('Sunglasses velvet display pad',(x,y-.005,z),(.31,.026,.15),'D1B0A1',.010)
    for dx in (-.066,.066):
        b.ring('Sunglasses frame',(x+dx,y+.060,z+.038),.057,.044,tone,.012)
        solid(ellipsoid('Dark sunglass lens',(x+dx,y+.060,z+.036),(.093,.069,.009),'464746',12,7))
    tube('Sunglasses nose bridge',[(x-.014,y+.069,z+.038),(x+.014,y+.069,z+.038)],.009,tone,5)
    for dx in (-.115,.115):tube('Sunglass folded arm',[(x+dx,y+.061,z+.025),(x+dx,y+.025,z-.05)],.009,tone,5)

def ring_tray(x,y,z):
    cube('Gold edged ring tray',(x,y+.016,z),(.32,.032,.22),'CD9F58',.015)
    cube('Pink velvet ring lining',(x,y+.037,z),(.28,.016,.18),'BF7E99',.012)
    for i in range(3):
        xx=x-.09+i*.09;b.ring('Upright ring in velvet slot',(xx,y+.069,z),.028,.032,'E0B858',.006)
        solid(ellipsoid('Ring gemstone',(xx,y+.103,z+.008),(.026,.023,.018),['8BACBE','EEC0D1','A8C5AE'][i],8,5))

def jewelry():
    rec=k.KITS['jewelry_display'];k.CURRENT=rec
    keep=['Sage jewelry cabinet','Jewelry brass bottom line','Display linen lining','Jewelry brass corner','Case long top rail','Case end top rail']
    for o in list(rec['objects']):
        if not any(o.name.startswith(t) for t in keep):rec['objects'].remove(o);k.bpy.data.objects.remove(o,do_unlink=True)
    necklace_bust(-.78,.468,-.095,True);necklace_bust(-.24,.468,-.095,False)
    earrings(.41,.47,-.095,'91B7CC');earrings(.88,.47,-.095,'D58EA9')
    ring_tray(-.88,.47,.20);ring_tray(.88,.47,.20)
    glasses(-.44,.485,.20,'33343B');glasses(.01,.485,.20,'C79F51')
    for x in (.36,.59):
        cube('Stud earring presentation card',(x,.495,.205),(.16,.046,.16),'DABEA8',.015)
        for dx in (-.040,.040):solid(ellipsoid('Pearl stud earring',(x+dx,.53,.205),(.037,.035,.029),'EFEAD9',10,6))

def footwear(kind,color):
    for x in (-.115,.115):
        if kind=='sneaker':
            sole=[(x+math.sin(j*math.tau/24)*.096,y,.012+math.cos(j*math.tau/24)*.203) for y in (.001,.054) for j in range(24)]
            faces=[tuple(reversed(range(24))),tuple(range(24,48))]+[(j,(j+1)%24,(j+1)%24+24,j+24) for j in range(24)]
            mesh('White sneaker shaped sole',sole,faces,'E8E3D8',smooth=True)
            ellipsoid('Sneaker enclosed upper',(x,.104,.047),(.179,.15,.32),color,20,9)
            cube('Padded sneaker heel',(x,.138,-.100),(.170,.17,.14),color,.042,'cloth')
            ellipsoid('Sneaker opening',(x,.227,-.105),(.110,.009,.096),'AC9F91',16,6)
            for j in range(4):tube('White laces',[(x-.06,.167,-.03+j*.031),(x+.06,.167,-.015+j*.031)],.006,'F5EFDF',5)
            continue
        heel=kind=='heel';n=24;vs=[]
        for ring in range(3):
            for j in range(n):
                a=j*math.tau/n;c=math.cos(a);sn=math.sin(a)
                if ring==0:xx=x+sn*.085;zz=c*.20;yy=.023+(.115*(1-c)/2 if heel else 0)
                elif ring==1:xx=x+sn*.082;zz=c*.20;yy=.078+(1-c)*(.075 if heel else .031)
                else:xx=x+sn*.051;zz=-.058+c*.083;yy=.111+(1-c)*(.061 if heel else .018)
                vs.append((xx,yy,zz))
        faces=[]
        for row in range(2):
            for j in range(n):faces.append((row*n+j,row*n+(j+1)%n,(row+1)*n+(j+1)%n,(row+1)*n+j))
        mesh('Pointed pump upper with open throat' if heel else 'Mary Jane closed round upper',vs,faces,color,smooth=True)
        cylinder('Shoe heel',(x,.073 if heel else .022,-.139),.027 if heel else .055,.146 if heel else .044,'C79171' if heel else '302E33',vertices=10)
        ellipsoid('Visible warm shoe insole',(x,.092 if heel else .048,-.060),(.106,.012,.178),'D6B797',16,6)
        tube('Shoe open rim',vs[2*n:]+[vs[2*n]],.006,color,5)
        if not heel:
            sole=[(x+math.sin(j*math.tau/24)*.088,y,.007+math.cos(j*math.tau/24)*.201) for y in (.001,.032) for j in range(24)]
            faces=[tuple(reversed(range(24))),tuple(range(24,48))]+[(j,(j+1)%24,(j+1)%24+24,j+24) for j in range(24)]
            mesh('Mary Jane shaped oval sole',sole,faces,'302E33',smooth=True)
            tube('Mary Jane instep strap',[(x-.074,.100,-.012),(x-.048,.140,-.012),(x+.048,.140,-.012),(x+.074,.100,-.012)],.014,color,7)
            solid(ellipsoid('Mary Jane gold buckle',(x+.07,.124,-.01),(.025,.03,.019),'D3A84F',8,5))

def shirt(style,color):
    b.hanger()
    if style=='long_v':
        pts=[(-.16,-.21),(-.25,-.28),(-.32,-.77),(-.23,-.78),(-.16,-.46),(-.16,-.79),(.16,-.79),(.16,-.46),(.23,-.78),(.32,-.77),(.25,-.28),(.16,-.21),(.08,-.24),(0,-.36),(-.08,-.24)]
        neck=[(-.08,-.24,.090),(0,-.36,.091),(.08,-.24,.090)]
    else:
        pts=[(-.16,-.21),(-.28,-.28),(-.33,-.49),(-.21,-.53),(-.17,-.40),(-.16,-.74),(.16,-.74),(.17,-.40),(.21,-.53),(.33,-.49),(.28,-.28),(.16,-.21),(.09,-.23),(.06,-.29),(-.06,-.29),(-.09,-.23)]
        if style=='boat':pts[-4:]=[(.09,-.24),(.06,-.25),(-.06,-.25),(-.09,-.24)]
        neck=[(-.095,-.23,.090),(-.065,-.285,.092),(0,-.31,.092),(.065,-.285,.092),(.095,-.23,.090)]
    b.extruded('Different neckline and sleeve blouse '+style,pts,.16,color,.024)
    tube('Blouse neckline',neck,.010,'EEE2CF',6)
    if style=='polo':
        for side in (-1,1):solid(mesh('Pointed polo collar',[(side*.10,-.235,.091),(side*.115,-.32,.094),(side*.035,-.30,.094),(0,-.245,.091)],[(0,1,2,3)],'E9DECD'))
        for y in (-.34,-.40):solid(ellipsoid('Polo button',(0,y,.092),(.016,.016,.008),'D9BA81',8,5))
    elif style=='flower':
        for j in range(5):
            a=j*math.tau/5;solid(ellipsoid('Blouse flower print',(.055*math.cos(a),-.47+.055*math.sin(a),.092),(.067,.061,.006),'D083A1',8,5))
        solid(ellipsoid('Blouse flower heart',(0,-.47,.096),(.043,.043,.006),'D9AD60',8,5))
    elif style=='boat':
        for y in (-.40,-.48,-.56):solid(cube('Blouse contrast stripe',(0,y,.085),(.29,.020,.008),'EFDCE0',0))
    else:
        solid(cube('Small embroidered chest pocket',(.078,-.45,.086),(.081,.079,.009),'7DAB9F',.008))

def remove_instance(name):
    for p in list(k.INSTANCES):
        if p['name']==name:
            o=k.bpy.data.objects[name]
            for child in list(o.children):k.bpy.data.objects.remove(child,do_unlink=True)
            k.bpy.data.objects.remove(o,do_unlink=True);k.INSTANCES.remove(p)

def stable_trim():
    for rec in k.KITS.values():
        for o in rec['objects']:
            if any(t in o.name.lower() for t in ['handle','piping','neckline','knit rib','moulding','stile','panel rail','frame','rug stitching','edge stitching','lace']):o['atlas_constant_colour']=True

def revise():
    petal_lamp();jewelry()
    for name,kind,color in [('pink_pumps','heel','D287A0'),('black_pumps','mary','36343C'),('ivory_sneakers','sneaker','E5E1D8'),('mint_mary_janes','mary','749A8E')]:r.clear(name);footwear(kind,color)
    names=['hanging_blouse_blue','hanging_blouse_ivory','hanging_blouse_mint','hanging_blouse_rose']
    for j,(name,style,color) in enumerate(zip(names,['polo','flower','long_v','boat'],['8FAFC8','E9DDCE','A8C2AD','D797AD'])):
        if name in k.KITS:r.clear(name)
        else:begin(name,at=(.62+j*.325,2.23,-2.25))
        shirt(style,color)
    remove_instance('right_upper_3')
    for p in k.INSTANCES:
        if p['name'].startswith('right_upper_'):p['asset']=names[int(p['name'][-1])%4]
        if p['name'].startswith('right_lower_'):p['asset']=names[(int(p['name'][-1])+1)%4]
    r.move('ivory_sneakers',(.60,.68,.25));k.KITS['ivory_sneakers']['yaw']=0;k.KITS['ivory_sneakers']['root'].rotation_euler.z=0
    r.move('pink_entry_mat',(-2.52,.079,1.50))
    stable_trim()
    r.sync_instances()

def manifest(d):
    d['revision']='R2'
    d['material_overrides']['petal_pendant']={'emission':'FFE4B2','emission_energy':.10,'emission_use_atlas':True}
    d['material_overrides']['flower_pendant_glow']={'emission':'FFE6B4','emission_energy':.6}
    d['material_overrides']['jewelry_glass']={'alpha':.035}
    from liubei_r2 import fit_camera
    fit_camera(d,(1489,1544),[(0,912),(751,1440),(1453,1006)],footprint=(6.16,5.76),plinth_y=-.255)
    d['review_views']=[{'name':'petal-lamp-detail','position':[-.1,3.7,1.4],'target':[-1.63,3.03,-1.94],'size':1.55},{'name':'jewelry-detail','position':[5.5,2.6,3.4],'target':[2.43,.77,1.13],'size':2.9},{'name':'footwear-detail','position':[.3,2.3,3.2],'target':[-.26,.84,.25],'size':2.45},{'name':'blouse-detail','position':[3.9,2.8,2.8],'target':[1.65,1.50,-2.25],'size':2.9}]
