"""Editable shop construction details for the warm-wood scene family."""
from scene_room_pipeline import *
import scene_room_pipeline as p


def counter(name,at,width=2.8,depth=.78,height=1.15,color='sage',yaw=0):
    begin(name,at,yaw,[{'at':[0,height/2,0],'size':[width,height,depth]}])
    cube('Counter carcass',(0,height/2,0),(width,height,depth),color,.045,'wood','Y')
    for x in (-width/2+.055,width/2-.055):cube('Counter corner stile',(x,height/2,depth/2+.025),(.115,height,.075),'oak',.023,'wood','Y')
    for i in range(round(width/.23)):
        x=-width/2+.16+i*.23
        if x<width/2-.1:cube('Counter tongue groove',(x,height/2,depth/2+.012),(.012,height-.16,.016),'sage_dark' if color=='sage' else 'oak_dark',.003)
    cube('Counter foot rail',(0,.09,depth/2+.015),(width+.07,.16,.10),'oak_edge',.022,'wood')
    cube('Counter thick oak top',(0,height+.055,0),(width+.2,.15,depth+.18),'oak_light',.05,'wood')


def worktable(name,at,width=2.5,depth=1.15,height=.98,yaw=0):
    begin(name,at,yaw,[{'at':[0,height/2,0],'size':[width,height,depth]}])
    for x in (-width/2+.12,width/2-.12):
        for z in (-depth/2+.11,depth/2-.11):cube('Workbench leg',(x,height/2,z),(.16,height,.16),'oak',.033,'wood','Y')
    for j in range(5):cube('Workbench top plank',(0,height,-depth*.4+j*depth*.2),(width+.13,.15,depth*.197),'oak_light' if j%3 else 'oak',.022,'wood')
    cube('Workbench lower shelf',(0,.18,0),(width-.14,.11,depth-.08),'oak',.025,'wood')
    for z in (-depth/2+.08,depth/2-.08):cube('Workbench stretcher',(0,height-.15,z),(width-.14,.15,.10),'oak_edge',.02,'wood')


def crate(at=(0,0,0),width=.65,height=.45,depth=.48,color='oak'):
    x,y,z=at
    cube('Crate bottom',(x,y+.04,z),(width,.08,depth),color,.018,'wood')
    for dx in (-width/2+.03,width/2-.03):
        for dz in (-depth/2+.03,depth/2-.03):cube('Crate corner',(x+dx,y+height/2,z+dz),(.065,height,.065),'oak_edge',.015,'wood','Y')
    for j in range(3):
        yy=y+.11+j*(height-.1)/3
        for dz in (-depth/2,depth/2):cube('Crate open slat',(x,yy,z+dz),(width,.09,.045),color,.011,'wood')
        for dx in (-width/2,width/2):cube('Crate side slat',(x+dx,yy,z),(.045,.09,depth),color,.011,'wood','Z')


def tool_bin(at=(0,0,0),radius=.34,height=.80,water=False):
    x,y,z=at
    for i in range(16):
        a=2*math.pi*i/16
        pts=[]
        for h,r in [(0,.88),(.12,.97),(.5,1.04),(.88,.97),(1,.88)]:pts.append((x+math.cos(a)*radius*r,y+h*height,z+math.sin(a)*radius*r))
        tube('Barrel individual oak stave',pts,radius*.205,'oak' if i%3 else 'oak_light',4)
    for yy,r in [(height*.12,radius*.98),(height*.85,radius*.99)]:
        lathe('Iron barrel hoop',(x,y+yy,z),[(0,r+.028),(.08,r+.028),(.08,r+.01),(0,r+.01)],'iron_edge',32)
        for i in range(12):
            a=i*math.pi/6;ellipsoid('Hoop rivet',(x+math.cos(a)*(r+.039),y+yy+.04,z+math.sin(a)*(r+.039)),(.035,.035,.035),'iron',8,6)
    cylinder('Barrel inside',(x,y+height*.25,z),radius*.8,.08,'oak_dark',vertices=24)
    if water:cylinder('Quenching water',(x,y+height*.82,z),radius*.81,.025,'446978',vertices=32)


def barrel(at=(0,0,0),radius=.34,height=.80,water=False,lid=True):
    x,y,z=at;profile=[(0,.88),(.12,.97),(.5,1.04),(.88,.97),(1,.88)]
    for i in range(16):
        angles=[2*math.pi*i/16+.009,2*math.pi*(i+1)/16-.009]
        verts=[]
        for inner in (False,True):
            for h,r in profile:
                for a in angles:
                    rr=radius*r-(.042 if inner else 0)
                    verts.append((x+math.cos(a)*rr,y+h*height,z+math.sin(a)*rr))
        n=len(profile)*2;faces=[]
        for j in range(len(profile)-1):
            k=j*2;faces += [(k,k+1,k+3,k+2),(n+k+2,n+k+3,n+k+1,n+k),
                            (k,k+2,n+k+2,n+k),(k+1,n+k+1,n+k+3,k+3)]
        faces += [(0,n,n+1,1),(n-2,n-1,2*n-1,2*n-2)]
        o=mesh('Curved coopered oak stave',verts,faces,'oak_light' if i%4==0 else 'oak','wood')
        mod=o.modifiers.new('Soft stave edge','BEVEL');mod.width=.008;mod.segments=2
        mod=o.modifiers.new('Stave corner normals','WEIGHTED_NORMAL');mod.keep_sharp=True
    for yy in (height*.12,height*.85):
        r=radius*.98;verts=[];faces=[];segments=32
        for dy,rr in [(0,r+.024),(.07,r+.024),(.07,r+.006),(0,r+.006)]:
            for i in range(segments):
                a=i*2*math.pi/segments;verts.append((x+rr*math.cos(a),y+yy+dy,z+rr*math.sin(a)))
        for j in range(4):
            for i in range(segments):faces.append((j*segments+i,j*segments+(i+1)%segments,((j+1)%4)*segments+(i+1)%segments,((j+1)%4)*segments+i))
        mesh('Continuous iron barrel hoop',verts,faces,'iron_edge',smooth=True)
        for i in range(12):
            a=i*math.pi/6;ellipsoid('Hoop rivet',(x+math.cos(a)*(r+.032),y+yy+.035,z+math.sin(a)*(r+.032)),(.028,.028,.028),'iron',8,6)
    cylinder('Barrel interior floor',(x,y+height*.12,z),radius*.82,.05,'oak_dark',vertices=24)
    if lid and not water:
        cylinder('Round wooden barrel lid',(x,y+height*.965,z),radius*.84,.05,'oak_light',vertices=32)
        for dx in (-.45,0,.45):
            span=radius*.80*math.sqrt(1-dx*dx)
            tube('Lid board seam',[(x+radius*dx,y+height*.994,z-span),(x+radius*dx,y+height*.994,z+span)],.006,'oak_edge',4)
    if water:cylinder('Quenching water',(x,y+height*.82,z),radius*.80,.018,'446978',vertices=32)


def pot(at=(0,0,0),radius=.17,height=.30,color='terra'):
    lathe('Open terracotta pot',at,[(0,radius*.68),(.04,radius*.75),(height*.83,radius),(height*.87,radius*1.1),(height,radius*1.1),(height,radius*.87),(height*.84,radius*.86),(.05,radius*.55)],color,20)


def bottle(at=(0,0,0),color='sage_dark',height=.36):
    x,y,z=at;r=height*.23
    lathe('Glass or ceramic bottle',at,[(0,r*.86),(.035,r),(height*.58,r),(height*.73,r*.43),(height*.94,r*.43),(height,r*.49)],color,16)
    cylinder('Bottle cork',(x,y+height+.014,z),r*.43,.045,'oak_edge',vertices=12)
    cube('Bottle paper label',(x,y+height*.39,z+r),(.10,height*.28,.012),'linen',.012)


def shelf(name,at,width=1.35,height=1.8,depth=.35,levels=4,yaw=0):
    begin(name,at,yaw)
    for x in (-width/2+.05,width/2-.05):cube('Shelf upright',(x,height/2,0),(.10,height+.12,depth),'oak',.025,'wood','Y')
    cube('Shelf backing',(0,height/2,-depth*.40),(width,height,.055),'oak_edge',.025,'wood','Y')
    for i in range(levels):cube('Display shelf',(0,i*height/(levels-1),depth*.05),(width+.10,.09,depth+.10),'oak_light',.024,'wood')


def sign(name,text,at,width=2.0,height=.62,yaw=0,color='sage_dark',letter_color='linen'):
    begin(name,at,yaw)
    cube('Carved sign wood border',(0,0,0),(width+.12,height+.12,.10),'oak',.075,'wood')
    cube('Painted sign panel',(0,0,.064),(width,height,.035),color,.04,'wood')
    lettering(text,(0,-height*.11,.09),width*.88,letter_color)
    for x in (-width*.38,width*.38):tube('Sign hanging hook',[(x,height/2+.05,-.04),(x,height/2+.23,.035),(x,height/2+.07,.12)],.026,'iron',8)


def register(at=(0,0,0)):
    x,y,z=at
    cube('Register cash drawer',(x,y+.11,z),(.54,.20,.39),'iron_edge',.04)
    cube('Register housing',(x,y+.25,z-.04),(.39,.18,.26),'iron',.03)
    cube('Register screen frame',(x,y+.48,z-.12),(.48,.33,.065),'iron_edge',.025)
    cube('Register dark screen',(x,y+.48,z-.078),(.40,.24,.02),'293334',.012)
    for i in range(3):
        for j in range(4):cube('Register key',(x-.14+j*.09,y+.35,z+.015+i*.045),(.06,.018,.035),'iron_edge',.004)
    cube('Cash drawer pull',(x,y+.10,z+.215),(.13,.022,.016),'brass',.006)


def watering_can(at=(0,0,0),color='sage_dark'):
    x,y,z=at
    lathe('Watering can body',at,[(0,.13),(.025,.17),(.30,.16),(.36,.125),(.36,.09),(.31,.085)],color,20)
    tube('Arched watering handle',[(x-.13,y+.22,z),(x-.17,y+.47,z),(x+.11,y+.48,z),(x+.15,y+.25,z)],.022,color,8)
    tube('Watering spout',[(x+.12,y+.08,z),(x+.28,y+.19,z),(x+.42,y+.43,z)],.035,color,10)
    o=cylinder('Perforated rose',(x+.43,y+.45,z),.076,.03,'iron_edge',vertices=16);o.rotation_euler.y=-.58


def garden_tool(kind,at=(0,0,0),height=1.5):
    x,y,z=at
    tube('Ash tool shaft',[(x,y+.25,z),(x,y+height-.10,z)],.032,'oak_light',8)
    if kind in ('shovel','fork'):
        tube('D grip',[(x-.08,y+height-.16,z),(x-.09,y+height,z),(x+.09,y+height,z),(x+.08,y+height-.16,z)],.025,'sage_dark',8)
    if kind=='shovel':
        verts=[(x-.13,y+.34,z),(x+.13,y+.34,z),(x+.14,y+.16,z+.045),(x,y+.02,z+.085),(x-.14,y+.16,z+.045)]
        o=mesh('Curved shovel blade',verts,[(0,1,2,3,4)],'iron_edge',smooth=True);o.modifiers.new('Blade thickness','SOLIDIFY').thickness=.026
    elif kind=='fork':
        tube('Fork shoulder',[(x-.13,y+.32,z),(x+.13,y+.32,z)],.023,'iron',8)
        for i in range(4):tube('Fork tine',[(x-.13+i*.087,y+.33,z),(x-.13+i*.087,y+.06,z+.035)],.018,'iron',8)
    else:
        cube('Rake transverse head',(x,y+.20,z),(.43,.06,.06),'iron',.015)
        for i in range(7):tube('Rake tooth',[(x-.19+i*.063,y+.20,z),(x-.19+i*.063,y+.10,z+.11)],.014,'iron',6)


def seed_packet(at=(0,0,0),color='sage',crop=0):
    x,y,z=at
    cube('Folded seed packet',(x,y+.17,z),(.25,.35,.07),color,.015)
    cube('Seed paper label',(x,y+.17,z+.043),(.205,.285,.02),'linen',.005)
    if crop%3==0:
        ellipsoid('Packet tomato',(x,y+.16,z+.064),(.12,.12,.012),'D9653E',12,8)
        leaf('Packet stem',(x,y+.21,z+.07),(x+.035,y+.28,z+.07),.035,'leaf')
    elif crop%3==1:
        for yy in (.08,.16,.23):leaf('Packet sprout',(x,y+yy,z+.067),(x+.07,y+yy+.06,z+.067),.055,'sage')
    else:
        ellipsoid('Packet flower heart',(x,y+.17,z+.07),(.065,.065,.01),'pollen',12,8)
        for i in range(8):
            a=i*math.pi/4;ellipsoid('Packet flower petal',(x+math.cos(a)*.068,y+.17+math.sin(a)*.068,z+.063),(.047,.047,.009),'EABC48',10,6)


def lantern(name,at,yaw=0):
    begin(name,at,yaw)
    cube('Lantern warm glass',(0,0,0),(.21,.28,.21),'FFCE73',.025)
    for x in (-.12,.12):
        for z in (-.12,.12):tube('Lantern metal corner',[(x,-.16,z),(x,.17,z)],.02,'iron_edge',6)
    cube('Lantern metal base',(0,-.18,0),(.31,.06,.31),'iron_edge',.03)
    cylinder('Lantern peaked roof',(0,.23,0),.23,.13,'iron_edge',top=.06,vertices=4)
    tube('Lantern hanger',[(0,.28,0),(0,.43,0),(0,.48,-.07),(0,.43,-.16)],.022,'iron',8)


def wall_window(name,wall_name,offset=0,width=.92,bottom=1.45,shoulder=2.35,rise=.15):
    wall=p.KITS[wall_name];p.b.CURRENT=wall
    target=next(o for o in wall['objects'] if 'plaster infill' in o.name)
    cut=arch_solid('Real window aperture',width,bottom,shoulder,rise,.75,0,'plaster')
    cut.location.x=offset;boolean_cut(target,cut)
    at=list(wall['at']);yaw=wall['yaw']
    if yaw==90:at[0]+=.105;at[2]-=offset
    else:at[0]+=offset;at[2]+=.105
    begin(name,at,yaw)
    arch_trim('Arched shop window casing',width,bottom,shoulder,rise,.10,.16,.04,'oak_light')
    cube('Deep shop window sill',(0,bottom,.12),(width+.30,.12,.37),'oak_light',.035,'wood')
    cube('Window vertical mullion',(0,(bottom+shoulder+rise)/2,0),(.065,shoulder+rise-bottom,.065),'oak',.009,'wood','Y')
    cube('Window horizontal mullion',(0,(bottom+shoulder)/2,0),(width,.065,.065),'oak',.009,'wood')
    begin(name+'_garden',at,yaw)
    p.b.painted_garden()
    o=p.KITS[name+'_garden']['objects'][0]
    for vertex in o.data.vertices:
        vertex.co.x*=width/2.3
        vertex.co.z=bottom-.08+(vertex.co.z-1.18)/(3.20-1.18)*(shoulder+rise-bottom+.16)


def round_table(name,at,radius=.70,height=.89):
    begin(name,at,collision=[{'at':[0,height/2,0],'size':[radius*2,height,radius*2]}])
    cylinder('Round timber tabletop',(0,height,0),radius,.13,'oak_light',vertices=48)
    lathe('Turned table pedestal',(0,.04,0),[(0,.31),(.07,.27),(.14,.15),(.57,.10),(.69,.16),(.78,.20)],'oak',24)
    for a in (0,2.094,4.189):tube('Table splayed foot',[(0,.10,0),(radius*.68*math.cos(a),.04,radius*.68*math.sin(a))],.065,'oak_edge',8)
