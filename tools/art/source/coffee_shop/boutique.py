"""Editable shared fixtures for Clothing Store B/A. Static display garments, not avatar clothing."""
import math,random
import bpy
import kit as k
from kit import begin,cube,cylinder,tube,ellipsoid,lathe,leaf

def extruded(name,points,depth,color,bevel=.018,kind='cloth'):
    n=len(points)
    verts=[(x,y,z) for z in (-depth/2,depth/2) for x,y in points]
    faces=[tuple(reversed(range(n))),tuple(n+i for i in range(n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    o=k.mesh(name,verts,faces,color,kind,True)
    if bevel:
        m=o.modifiers.new('Soft fabric edges','BEVEL');m.width=bevel;m.segments=3
        m=o.modifiers.new('Cloth surface normals','WEIGHTED_NORMAL');m.keep_sharp=True
    return o

def ring(name,at,rx,ry,color,r=.009):
    x,y,z=at
    return tube(name,[(x+math.cos(j*math.tau/32)*rx,y+math.sin(j*math.tau/32)*ry,z) for j in range(33)],r,color,6)

def hanger():
    tube('Hanger hook',[(.03,.09,0),(.075,.06,0),(.069,.013,0),(0,-.025,0),(0,-.105,0)],.012,'brass',8)
    tube('Wood clothes hanger',[(0,-.11,0),(-.25,-.23,0),(-.21,-.25,0),(.21,-.25,0),(.25,-.23,0),(0,-.11,0)],.019,'oak_light',8,'wood')

def garment(color='E5ACAF',kind='dress',pattern=False):
    """Mount pivot at the hanger rail; garment extends downward."""
    hanger()
    long=kind in ('hoodie','varsity')
    if long:
        p=[(-.18,-.21),(-.29,-.28),(-.37,-.89),(-.25,-.92),(-.20,-.55),(-.20,-.96),(.20,-.96),(.20,-.55),(.25,-.92),(.37,-.89),(.29,-.28),(.18,-.21),(.10,-.22),(.075,-.30),(-.075,-.30),(-.10,-.22)]
    else:
        p=[(-.16,-.21),(-.26,-.27),(-.31,-.52),(-.21,-.55),(-.17,-.42),(-.155,-.73),(.155,-.73),(.17,-.42),(.21,-.55),(.31,-.52),(.26,-.27),(.16,-.21),(.085,-.235),(.062,-.30),(-.062,-.30),(-.085,-.235)]
    extruded('Tailored garment body',p,.15,color,.026)
    tube('Neckline piping',[(-.10,-.225,.084),(-.076,-.285,.086),(0,-.315,.087),(.076,-.285,.086),(.10,-.225,.084)],.013,'porcelain' if kind!='hoodie' else color,6)
    if kind=='dress':
        verts=[];faces=[];n=36
        for y,rx,rz in [(-.69,.157,.079),(-.84,.19,.11),(-1.08,.24,.15),(-1.34,.29,.19)]:
            for j in range(n):
                a=j*math.tau/n;pleat=1+.045*math.cos(a*12)
                verts.append((math.cos(a)*rx*pleat,y,math.sin(a)*rz*pleat))
        for row in range(3):
            for j in range(n):faces.append((row*n+j,row*n+(j+1)%n,(row+1)*n+(j+1)%n,(row+1)*n+j))
        faces.append(tuple(3*n+j for j in reversed(range(n))))
        k.mesh('Flared pleated skirt',verts,faces,color,'cloth',True)
        for x in (-.245,.245):ellipsoid('Puff sleeve',(x,-.37,0),(.18,.27,.20),color,16,10,'cloth')
        tube('Dress hem piping',[(math.cos(j*math.tau/n)*.29,-1.337,math.sin(j*math.tau/n)*.19) for j in range(n+1)],.009,'porcelain',6)
        cube('Waist ribbon',(0,-.70,.089),(.33,.042,.018),'D7899F' if color!='D7899F' else 'porcelain',.012)
        for x in (-.043,.043):ellipsoid('Ribbon bow loop',(x,-.70,.117),(.087,.055,.025),'D7899F',12,6)
        if pattern:
            for j in range(12):
                y=-.87-(j//4)*.145;x=-.15+(j%4)*.10;z=.12+(abs(y)-.85)*.17
                ellipsoid('Dress polka dot',(x,y,z),(.043,.053,.009),'porcelain',8,5)
    elif kind=='hoodie':
        ellipsoid('Soft hood behind collar',(0,-.24,-.065),(.32,.29,.24),color,20,12,'cloth')
        cube('Kangaroo pocket',(0,-.78,.086),(.29,.14,.021),color,.038,'cloth')
        for x in (-.067,.067):tube('Hood cord',[(x,-.33,.099),(x,-.51,.105)],.006,'porcelain',5)
        for j in range(6):
            x=-.12+j*.045
            tube('Original shirt stroke',[(x,-.50,.088),(x+.07,-.60,.09),(x-.015,-.64,.09)],.006,'porcelain',5)
    elif kind=='varsity':
        for x in (-.30,.30):
            cube('Varsity contrast sleeve',(x,-.59,.008),(.12,.59,.18),'porcelain',.055,'cloth')
            for y in (-.85,-.91):cube('Varsity sleeve cuff stripe',(x,y,.107),(.135,.018,.008),'iron',.005)
        for y in (-.89,-.94):cube('Varsity hem stripe',(0,y,.091),(.38,.016,.01),'porcelain',.004)
        k.text_label('B',(.083,-.58,.092),.21,'porcelain')
        for j in range(5):ellipsoid('Jacket button',(-.012,-.39-j*.105,.10),(.018,.018,.008),'porcelain',8,4)
    else:
        cube('Shirt hem',(0,-.721,.0),(.315,.022,.16),color,.008,'cloth')

def trousers(color='697057'):
    cube('Trousers waistband',(0,.84,0),(.40,.10,.18),color,.02,'cloth')
    for side in (-1,1):
        cube('Cargo trouser leg',(side*.105,.44,0),(.185,.76,.19),color,.036,'cloth')
        cube('Cargo side pocket',(side*.17,.51,.098),(.12,.20,.037),color,.015,'cloth')
        cube('Trouser cuff',(side*.105,.07,0),(.19,.048,.19),color,.014,'cloth')
    tube('Trouser drawcord',[(-.035,.845,.10),(0,.78,.11),(.035,.845,.10)],.006,'porcelain',5)

def rack(width=2.23,metal='brass',shelf='E4C277',lower=True):
    for x in (-width/2,width/2):
        tube('Garment rack upright',[(x,.06,0),(x,2.46,0),(x*.96,2.53,0)],.035,metal,10)
        ellipsoid('Rack foot',(x,.065,0),(.16,.11,.17),metal,12,6)
    tube('Hanger rail',[(-width/2,2.16,.05),(width/2,2.16,.05)],.028,metal,10)
    cube('Top bag shelf',(0,2.36,0),(width+.04,.065,.46),shelf,.026,'wood')
    if lower:cube('Lower rack shelf',(0,.18,0),(width+.03,.067,.49),shelf,.025,'wood')

def handbag(color='D9A8B0',bow=False):
    cube('Structured handbag',(0,.165,0),(.39,.33,.19),color,.075)
    cube('Bag curved flap',(0,.231,.101),(.37,.15,.030),color,.055)
    ring('Top handle',(0,.357,0),.10,.12,color,.023)
    button=cylinder('Bag gold clasp',(0,.169,.126),.031,.015,'brass',vertices=16);button.rotation_euler.x=math.pi/2
    if bow:
        for x in (-.049,.049):ellipsoid('Handbag bow loop',(x,.178,.135),(.102,.073,.036),'porcelain',12,7)
        ellipsoid('Bow knot',(0,.178,.15),(.047,.054,.03),color,10,6)

def folded(color='porcelain'):
    cube('Folded knit garment',(0,.055,0),(.39,.11,.31),color,.041,'cloth')
    for j in range(7):tube('Knit rib',[(-.145+j*.047,.102,-.12),(-.145+j*.047,.111,.08)],.003,color,4)
    tube('Folded neckline',[(-.07,.113,-.14),(-.047,.116,-.082),(0,.119,-.069),(.047,.116,-.082),(.07,.113,-.14)],.009,color,6)

def shoes(color='D996A7',street=False):
    for x in (-.105,.105):
        cube('Shoe sole',(x,.023,.02),(.17,.046,.36),'porcelain' if street else 'brass',.035)
        ellipsoid('Rounded shoe upper',(x,.085,.045),(.159,.12,.33),color,20,10)
        ellipsoid('Shoe inner opening',(x,.138,-.041),(.101,.012,.125),'iron',16,6)
        if street:
            cube('Sneaker ankle',(x,.158,-.084),(.148,.17,.139),color,.041,'cloth')
            cube('Sneaker toe cap',(x,.092,.147),(.151,.065,.102),'porcelain',.032)
            for j in range(4):tube('Sneaker lace',[(x-.057,.148,-.035+j*.033),(x+.057,.148,-.021+j*.033)],.006,'porcelain',5)
        else:
            for dx in (-.025,.025):ellipsoid('Pump bow',(x+dx,.13,.065),(.057,.028,.048),'porcelain',10,6)

def mirror(color='brass',surface='96C9D5'):
    k.arch_trim('Standing mirror frame',.65,.12,1.68,.33,.058,.09,0,color)
    k.arch_solid('Stylized mirror surface',.63,.14,1.68,.315,.018,.055,surface)
    for x in (-.30,.30):ellipsoid('Mirror foot',(x,.075,0),(.14,.12,.21),color,12,7)
    tube('Mirror back easel',[(0,1.31,-.07),(0,.10,-.39)],.025,color,8)
    # A deliberate broad highlight, not an environment reflection simulation.
    k.mesh('Mirror broad sheen',[(-.29,.47,.068),(.29,1.51,.068),(.29,1.78,.068),(-.29,.74,.068)],[(0,1,2,3)],'C7DFDF')

def curtain(color='D895A9',width=1.0,height=2.28):
    verts=[];faces=[];n=48
    for y in (.05,height):
        for j in range(n+1):verts.append((-width/2+j*width/n,y,.063*math.cos(j*math.tau/8)))
    for j in range(n):faces.append((j,j+1,n+2+j,n+1+j))
    o=k.mesh('Pleated changing curtain',verts,faces,color,'cloth',True)
    m=o.modifiers.new('Curtain thickness','SOLIDIFY');m.thickness=.012
    tube('Curtain rail',[(-width/2,height+.02,0),(width/2,height+.02,0)],.025,'brass',8)

def clip_poly(poly,axis,value,greater):
    out=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        ina=(a[axis]>=value) if greater else (a[axis]<=value);inb=(b[axis]>=value) if greater else (b[axis]<=value)
        if ina:out.append(a)
        if ina!=inb:
            t=(value-a[axis])/(b[axis]-a[axis]);p=[a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])];out.append(tuple(p))
    return out

def shell(street=False):
    wall='35363A' if street else 'EBC1B9';trim='2B2D31' if street else 'E79AAA'
    begin('boutique_floor',collision=[{'at':[0,-.105,0],'size':[6.1,.27,5.68]}])
    cube('Boutique slab',(0,-.115,0),(6.16,.28,5.76),'928B85' if street else 'ECD4C4',.12)
    if street:
        for i in range(12):
            for j in range(11):cube('Concrete floor tile',(-2.75+i*.5,.025,-2.5+j*.5),(.491,.047,.491),'9D9690' if (i+j)%3 else 'AAA29A',.012,'plaster')
    else:
        for col in range(8):
            x=-3+col*.75;shift=.43 if col%2==0 else -.43
            for row in range(-2,21):
                z=-3.20+row*.31
                poly=[(x+.008,z),(x+.742,z+shift),(x+.742,z+shift+.296),(x+.008,z+.296)]
                for axis,value,greater in [(0,-3,True),(0,3,False),(1,-2.73,True),(1,2.73,False)]:poly=clip_poly(poly,axis,value,greater) if poly else []
                if len(poly)>=3:
                    n=len(poly);verts=[(px,y,pz) for y in (.02,.058) for px,pz in poly]
                    faces=[tuple(range(n)),tuple(n+j for j in reversed(range(n)))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
                    k.mesh('Chevron parquet',verts,faces,'E6BD88' if (col+row)%3 else 'EDCB9D','wood')
    begin('boutique_left_wall',at=(-3,.06,0),yaw=90,collision=[{'at':[-2.64,1.5,0],'size':[.27,3,.20]},{'at':[.80,1.5,0],'size':[3.99,3,.20]}])
    slab=cube('Left boutique wall',(0,1.57,0),(5.61,3.14,.20),wall,.07,'plaster')
    cutter=k.arch_solid('Entrance cut',1.35,-.05,2.13,.36,.8,0,wall);cutter.location.x=-1.96;k.boolean_cut(slab,cutter)
    if not street:
        cutter=cube('Display opening',(-.50,1.60,0),(.84,1.99,.80),wall,.02);k.boolean_cut(slab,cutter)
    cube('Left wall crown',(0,3.15,0),(5.65,.12,.26),wall,.046)
    cube('Left skirting',(0,.09,.14),(5.60,.14,.08),trim,.018)
    for x in ((-.43,.73,1.94) if street else (.76,1.91)):
        cube('Left wall inset',(x,1.70,.112),(1.06,2.72,.028),'214D9A' if street else wall,.03)
        for dx in (-.55,.55):cube('Panel vertical moulding',(x+dx,1.70,.145),(.035,2.76,.028),trim,.012)
        for y in (.33,3.08):cube('Panel horizontal moulding',(x,y,.145),(1.12,.035,.028),trim,.012)
    begin('boutique_back_wall',at=(0,.06,-2.75),collision=[{'at':[0,1.57,0],'size':[6,3.14,.20]}])
    slab=cube('Rear boutique wall',(0,1.57,0),(6.05,3.14,.20),wall,.07,'plaster')
    cutter=k.arch_solid('Fitting room cut',1.03,-.05,2.12,.47,.80,0,wall);cutter.location.x=-1.62;k.boolean_cut(slab,cutter)
    cube('Rear crown',(0,3.15,0),(6.12,.12,.26),wall,.046)
    cube('Rear skirting',(0,.09,.14),(6.02,.14,.08),trim,.018)
    for x,width in ((-2.6,.59),(-.30,1.17),(1.68,2.32)):
        cube('Rear wall panel',(x,1.70,.113),(width,2.71,.022),'214D9A' if street else wall,.02)
        for dx in (-width/2,width/2):cube('Rear wall panel stile',(x+dx,1.70,.145),(.035,2.73,.03),trim,.012)
        for y in (.335,3.065):cube('Rear wall panel rail',(x,y,.145),(width,.035,.03),trim,.012)

def entrance(metal='brass'):
    begin('entrance_frame',at=(-2.87,.06,1.96),yaw=90)
    k.arch_trim('Double shop entrance frame',1.31,.035,2.13,.33,.05,.10,0,metal)
    cube('Entrance center rail',(0,1.18,.02),(.042,2.26,.08),metal,.018)
    for x in (-.13,.13):tube('Entrance pull',[(x,.84,.065),(x,.84,.135),(x,1.30,.135),(x,1.30,.065)],.022,metal,8)
    begin('entrance_glass',at=(-2.87,.06,1.96),yaw=90)
    k.arch_solid('Entrance glazing',1.25,.05,2.13,.29,.013,0,'porcelain')

def sconce(metal='brass'):
    cube('Wall lamp backplate',(0,0,0),(.095,.56,.035),metal,.03)
    lathe('Opal wall sconce',(0,-.245,.071),[(0,.049),(.035,.066),(.41,.066),(.46,.049)],'FFF0C6',16)
    cylinder('Sconce metal waist',(0,-.02,.072),.070,.12,metal,vertices=16)
