"""SGODOT-214 / 赵云. Stark 2681:135486 + checklist v1.1.

Deterministic editable room, shared 2048 albedo/AO, local-pivot modules.
Run Blender with this absolute path. --geometry-only skips baking/export.
All helper coordinates are Godot metres: Y up, front +Z.
"""
from pathlib import Path
import sys, math, json, random, subprocess, shutil
sys.path.insert(0, str(Path(__file__).resolve().parent))
from scene_room_pipeline import *
import scene_room_pipeline as p
from mathutils import Matrix

PALETTE = dict(
    oak='DE8252', oak_light='F39C72', oak_edge='C16C47', oak_end='EB9260',
    oak_dark='92583F', floor='EBA086', floor_light='F1AA90', floor_shade='E59A83',
    joint='CC8E71', plaster='F4DCD2', panel='8E9DAF', panel_light='A4B0BD',
    panel_edge='7B899D', cream='F3DDD0', brass='D99E4D', brass_light='F4C577',
    metal='737880', metal_light='9DA1A6', dark='414E50', navy='344D72',
    ivory='F3E1C9', red='D95051', blue='467AA2', yellow='E9B84E',
    reed='D7B77D', cork='B37D4D', rope='D6AC8B', terra='CC7750',
)

def bevel(o, width=.018, segments=2):
    m=o.modifiers.new('Soft handmade edge', 'BEVEL');m.width=width;m.segments=segments
    m=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');m.keep_sharp=True
    return o

def prism(name, outline, bottom, top, color, edge=.015):
    n=len(outline)
    verts=[(x,y,z) for y in (bottom,top) for x,z in outline]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    o=mesh(name,verts,faces,color)
    if edge:bevel(o,edge)
    return o

def ring(name, at, radius, thickness, color, plane='xy', segments=48, sides=6):
    x,y,z=at
    pts=[]
    for i in range(segments+1):
        a=2*math.pi*i/segments
        pts.append((x+radius*math.cos(a),y+radius*math.sin(a),z) if plane=='xy'
                   else (x+radius*math.cos(a),y,z+radius*math.sin(a)))
    return tube(name,pts,thickness,color,sides)

def disc(name,at,radius,depth,color,segments=32):
    o=cylinder(name,at,radius,depth,color,vertices=segments)
    o.rotation_euler.x=math.pi/2
    return o

def face_front(o):
    """An isolated planar polygon has no volume to orient its front reliably."""
    bm=bmesh.new();bm.from_mesh(o.data)
    bmesh.ops.reverse_faces(bm,faces=[f for f in bm.faces if f.normal.y>0])
    bm.to_mesh(o.data);bm.free()
    return o

def barrel_low(name='Float barrel',radius=.24,height=.46,segments=10):
    # Continuous open low-poly coopered barrel. Colored staves, not grain photos.
    verts=[]
    for y,r in [(0,radius*.86),(height*.48,radius),(height,radius*.9),
                (height,radius*.77),(height*.18,radius*.72)]:
        for i in range(segments):
            a=2*math.pi*i/segments;verts.append((r*math.cos(a),y,r*math.sin(a)))
    faces=[]
    for row in range(4):
        for i in range(segments):faces.append((row*segments+i,row*segments+(i+1)%segments,(row+1)*segments+(i+1)%segments,(row+1)*segments+i))
    faces += [tuple(reversed(range(segments))),tuple(4*segments+i for i in range(segments))]
    o=mesh(name+' open staves',verts,faces,'oak')
    o.data.materials.append(material('oak_light'))
    for i,f in enumerate(o.data.polygons):
        if i<segments*2 and i%segments%3==0:f.material_index=1
    for yy,rr in [(.12*height,radius*.92),(.79*height,radius*.97)]:
        lathe(name+' iron band',(0,yy,0),[(0,rr),(.035,rr),(.035,rr-.012),(0,rr-.012)],'metal',segments)
    return o

def float_prop(at, color='red',size=.12,segments=8):
    x,y,z=at
    # Two closed-color halves; 40 triangles at six segments.
    lathe('Float ivory belly',at,[(-size*.9,.003),(-size*.5,size*.67),(0,size*.82)],'ivory',segments)
    lathe('Float colored cap',at,[(0,size*.82),(size*.58,size*.64),(size*.91,.012)],color,segments)
    cylinder('Float short stem',(x,y+size*1.07,z),size*.12,size*.36,'oak_edge',vertices=4)

def architecture():
    begin('room_shell',(0,0,0),collision=[
        {'at':[0,-.08,0],'size':[6.8,.32,6.4]},
        {'at':[-3.27,1.65,0],'size':[.22,3.3,6.4]},
        {'at':[0,1.65,-3.07],'size':[6.8,3.3,.22]},
        {'at':[3.36,.75,0],'size':[.08,1.5,6.4]},
        {'at':[-2.05,.75,3.16],'size':[2.7,1.5,.08]},
        {'at':[2.05,.75,3.16],'size':[2.7,1.5,.08]},
        {'at':[0,-.08,3.48],'size':[1.4,.32,.64]},
        {'at':[-.74,.75,3.48],'size':[.08,1.5,.7]},
        {'at':[.74,.75,3.48],'size':[.08,1.5,.7]},
        {'at':[0,.75,3.84],'size':[1.5,1.5,.08]},
    ])
    cube('Warm timber foundation',(0,-.12,0),(6.8,.32,6.4),'oak_edge',.07)
    cube('Soft floor seams',(0,.024,0),(6.65,.05,6.25),'joint',.01)
    for row in range(19):
        z=-3.03+row*.33
        x=-3.26;j=0
        while x<3.26-.001:
            length=min(1.28 if j or row%2==0 else .64,3.26-x)
            cube('Floor plank %02d %02d'%(row,j),(x+length/2,.055,z),
                 (length-.008,.05,.322),['floor','floor_light','floor','floor_shade'][(row+j)%4],.008)
            x+=length;j+=1
    for x in (-3.31,3.31):cube('Long foundation trim',(x,-.015,0),(.18,.19,6.4),'oak_light',.025)
    for z in (-3.11,3.11):cube('Front foundation trim',(0,-.015,z),(6.44,.19,.18),'oak_light',.025)
    cube('Open exit wood landing',(0,-.015,3.47),(1.4,.19,.66),'oak_light',.025)
    for wall,at,yaw,length in [('left_wall',(-3.27,0,0),90,6.18),('back_wall',(0,0,-3.07),0,6.6)]:
        begin(wall,at,yaw)
        wall_mesh=cube('Pink white plaster',(0,1.65,-.04),(length,3.14,.18),'plaster',.018,'plaster')
        if wall=='left_wall':
            cut=disc('Real round porthole cutter',(1.37,2.08,-.04),.64,.7,'plaster',64)
            boolean_cut(wall_mesh,cut)
        for i in range(round(length/.26)):
            w=length/round(length/.26)
            cube('Blue grey vertical wainscot',(-length/2+w*(i+.5),.52,.062),(w-.009,.88,.08),
                 'panel_light' if i%5==0 else 'panel',.008)
        cube('Wainscot top rail',(0,1.0,.087),(length,.095,.13),'panel_light',.017)
        cube('Wainscot foot rail',(0,.115,.087),(length,.12,.13),'panel_edge',.016)
        for xx in (-length/2+.10,length/2-.10):
            cube('Orange timber post',(xx,1.65,.06),(.23,3.3,.29),'oak',.04)
            cube('Orange post joint cap',(xx,3.12,.06),(.35,.32,.35),'oak_end',.045)
            cube('Orange post foot',(xx,.12,.06),(.33,.24,.34),'oak_edge',.03)
        cube('Top cutaway beam',(0,3.18,.04),(length,.24,.29),'oak_light',.035)
        mid=.44 if wall=='left_wall' else 1.35
        cube('Intermediate slender upright',(mid,1.64,.055),(.14,3.12,.25),'oak',.025)

def porthole():
    begin('porthole',(-3.115,2.08,-1.37),90)
    # True circular aperture; metal rim and a separate replaceable landscape.
    n=64;vs=[]
    for z,r in [(-.10,.645),(.03,.73),(.095,.72),(.095,.595),(-.10,.595)]:
        for i in range(n):
            a=math.tau*i/n;vs.append((r*math.cos(a),r*math.sin(a),z))
    faces=[]
    for row in range(4):
        for i in range(n):faces.append((row*n+i,row*n+(i+1)%n,(row+1)*n+(i+1)%n,(row+1)*n+i))
    mesh('Porthole deep metal annulus',vs,faces,'metal',smooth=True)
    ring('Porthole warm inner lip',(0,0,.095),.595,.014,'ivory',segments=64)
    for i in range(12):
        a=math.tau*i/12
        disc('Porthole flat rivet',(.665*math.cos(a),.665*math.sin(a),.105),.019,.012,'metal_light',8)
    begin('porthole_view',(-3.39,2.08,-1.37),90)
    disc('Window sky',(0,0,0),.635,.008,'B9D8E3',64)
    # Low-contrast painted shapes, all confined to the window disk.
    mesh('Distant water',[(-.60,-.18,.009),(.60,-.18,.009),(.51,-.37,.009),(.28,-.56,.009),(-.28,-.56,.009),(-.51,-.37,.009)],[(0,1,2,3,4,5)],'87BBCD')
    mesh('Distant headland',[(.12,-.15,.013),(.20,.10,.013),(.39,.22,.013),(.56,.08,.013),(.62,-.05,.013),(.58,-.20,.013)],[(0,1,2,3,4,5)],'B6C6A4')
    for x,y,w in [(-.20,.29,.42),(.26,.40,.31)]:ellipsoid('Soft distant cloud',(x,y,.021),(w,.10,.018),'E8ECE6',16,8)

def counter():
    begin('curved_counter',(-.36,.08,-1.16),collision=[{'at':[0,.55,0],'size':[1.94,1.10,.88]}])
    # Shallow bowed front with real rounded ends, plain plaster panels.
    front=[(-1.03,-.25),(-1.03,.12),(-.94,.31),(-.73,.43),(-.37,.49),(.37,.49),(.73,.43),(.94,.31),(1.03,.12),(1.03,-.25)]
    front=[(x*.93,z) for x,z in front]
    prism('Cream curved counter body',front,.08,1.01,'cream',.035)
    prism('Bowed oak plinth',[(x*1.025,z*1.025) for x,z in front],.015,.14,'oak',.023)
    prism('Pale orange curved worktop',[(x*1.065,z*1.12) for x,z in front],1.02,1.12,'oak_light',.033)
    for x,z in [(-.91,.31),(-.45,.48),(.45,.48),(.91,.31)]:cube('Front slim wooden stile',(x*.93,.58,z+.015),(.055,.88,.058),'oak',.014)
    # Ship wheel on the front is a separate reusable module.
    begin('counter_ship_wheel',(-.36,.66,-.615))
    ring('Wheel outer brass wood rim',(0,0,0),.25,.028,'brass',segments=32,sides=8)
    ring('Wheel inner warm edge',(0,0,.009),.214,.009,'brass_light',segments=32,sides=5)
    disc('Wheel central hub',(0,0,.018),.065,.055,'brass',20)
    for i in range(8):
        a=math.tau*i/8;c,s=math.cos(a),math.sin(a)
        tube('Wheel radial spoke',[(c*.055,s*.055,0),(c*.316,s*.316,0)],.018,'brass',6)
        ellipsoid('Wheel rounded handle',(c*.319,s*.319,0),(.05,.05,.05),'brass_light',8,6)

def lantern_shape(scale=1):
    # A compact metal lamp around a softly glowing warm core.
    r=.105*scale;h=.28*scale
    lathe('Lantern amber glass',(0,.03*scale,0),[(0,r*.83),(h*.75,r*.83)],'FFE2A0',16)
    lathe('Lantern golden foot',(0,0,0),[(0,r),(.035*scale,r*1.17),(.06*scale,r)],'brass',20)
    lathe('Lantern bell cap',(0,h*.80,0),[(0,r*1.22),(.025*scale,r*1.2),(.085*scale,r*.55),(.11*scale,r*.28)],'brass',20)
    for a in [math.pi*.25+i*math.pi/2 for i in range(4)]:
        tube('Lantern frame',[(r*math.cos(a),.045*scale,r*math.sin(a)),(r*math.cos(a),h*.83,r*math.sin(a))],.009*scale,'brass',6)
    ring('Lantern top handle',(0,h+.03*scale,0),.045*scale,.008*scale,'brass',segments=16,sides=5)

def lamps():
    begin('counter_lantern',(-1.10,1.20,-1.16));lantern_shape(.80)
    begin('wall_lantern',(-3.03,2.33,.24),90)
    disc('Lantern wall rose',(0,.18,-.12),.09,.04,'brass',16)
    tube('Lantern curved wall hook',[(0,.18,-.12),(0,.31,-.10),(0,.34,.10),(0,.20,.15)],.016,'brass',8)
    lantern_shape(1.02)
    begin('pendant_lamp',(-1.5,2.47,-2.08))
    tube('Hanging lamp cord',[(0,.30,0),(0,.73,0)],.013,'dark',6)
    lathe('Deep grey bell shade',(0,.04,0),[(0,.24),(.04,.24),(.14,.15),(.21,.11),(.24,.07)],'dark',32)
    lathe('Ivory underside',(0,.025,0),[(0,.22),(.016,.22)],'ivory',32)
    ellipsoid('Pendant warm bulb',(0,-.035,0),(.105,.14,.105),'FFE5B2',16,10)

def rod_rack():
    begin('rod_rack',(-2.92,.08,.17),90,collision=[{'at':[0,.55,0],'size':[.94,1.10,.36]}])
    cube('Rack orange low base',(0,.19,0),(.9,.38,.35),'oak',0)
    for y in (.025,.375):cube('Rack face rail',(0,y,.181),(.9,.045,.02),'oak_light',0)
    for x in (-.42,.42):cube('Rack upright',(x,.57,-.10),(.06,1.14,.07),'oak_edge',0)
    cube('Rack upper support',(0,1.08,-.075),(.90,.07,.09),'oak_light',0)
    # Four separate holes in the top plate, beneath the seated rod butts.
    # Recessed dark disks avoid costly boolean cuts in this <=1200-triangle prop.
    for i in range(4):
        x=-.30+.20*i;tilt=(i-1.5)*.016;end=1.54+.045*(i%3)
        cylinder('Rod socket dark recess %d'%i,(x,.383,.015),.043,.002,'oak_dark',vertices=6)
        tube('Reed rod shaft %d'%i,[(x,.38,.015),(x+tilt*.4,.95,.015),(x+tilt,end,.015)],.0105,'reed',4)
        cylinder('Cork handle %d'%i,(x,.53,.015),.023,.26,'cork',vertices=6)
        disc('Matte reel spool %d'%i,(x,.64,.068),.047,.037,'metal',6)
        disc('Reel centre %d'%i,(x,.64,.091),.017,.012,'metal_light',5)
        tube('Reel short crank %d'%i,[(x+.021,.64,.097),(x+.058,.615,.097)],.007,'cork',4)
        for j in range(3):
            yy=.92+j*.24;xx=x+tilt*(yy-.38)/(end-.38)
            cylinder('Reed joint %d %d'%(i,j),(xx,yy,.015),.015,.019,'cork',vertices=4)
            mesh('Guide bump %d %d'%(i,j),[(xx,yy,.025),(xx+.023,yy,.024),(xx+.012,yy+.019,.024),(xx+.012,yy+.008,.037)],[(0,1,2),(0,3,1),(1,3,2),(2,3,0)],'metal')
        if i==3:float_prop((x+tilt+.045,end-.18,.024),'red',.048,6)
    begin('float_barrel',(-2.75,.08,-.68),collision=[{'at':[0,.24,0],'size':[.48,.48,.48]}])
    barrel_low(segments=8)
    for i,(x,z,col) in enumerate([(-.09,.035,'red'),(.09,.035,'blue'),(0,-.07,'red')]):float_prop((x,.50+(i%2)*.035,z),col,.075,6)
    instance('float_barrel','rafa_float_barrel',(3.00,.08,-1.68),yaw=15,scale=1.16)

def tin(at,color='blue',radius=.10,height=.20):
    x,y,z=at
    lathe('Striped tackle tin',at,[(0,radius*.9),(.02,radius),(height-.02,radius),(height,radius*.93)],color,16)
    cylinder('Tin pale stripe',(x,y+height*.45,z),radius*1.01,height*.22,'ivory',vertices=16)
    cylinder('Tin matte lid',(x,y+height+.008,z),radius*1.04,.027,'metal',vertices=16)

def box_prop(at,size=(.37,.28,.32)):
    x,y,z=at;w,h,d=size
    cube('Wood storage box',(x,y+h/2,z),size,'oak',.014)
    cube('Box lid',(x,y+h+.013,z),(w+.025,.035,d+.02),'oak_light',.008)
    cube('Box recessed handhold',(x,y+h*.70,z+d/2+.004),(w*.30,.037,.009),'oak_dark',.008)

def hat(at=(0,0,0),color='yellow',scale=1):
    x,y,z=at
    lathe('Soft round hat brim',at,[(0,.23*scale),(.025*scale,.26*scale),(.045*scale,.23*scale)],color,32)
    lathe('Rounded hat crown',(x,y+.03*scale,z),[(0,.16*scale),(.11*scale,.15*scale),(.19*scale,.10*scale),(.20*scale,.02*scale)],color,24)
    lathe('Warm hat ribbon',(x,y+.055*scale,z),[(0,.163*scale),(.035*scale,.16*scale)],'oak_edge',24)

def shelf_unit(name,at,width,height,depth):
    begin(name,at,collision=[{'at':[0,height/2,0],'size':[width,height,depth]}])
    for x in (-width/2+.045,width/2-.045):
        for z in (-depth/2+.04,depth/2-.04):cube('Open shelf leg',(x,height/2,z),(.09,height,.09),'oak',.019)
    for y in (.12,height*.49,height):
        for j in range(3):cube('Open shelf plank',(0,y,-depth/3+j*depth/3),(width+.035,.075,depth/3-.004),'oak_light',.012)

def shelves():
    shelf_unit('corner_open_shelf',(-2.30,.08,-2.56),1.18,1.97,.70)
    begin('corner_shelf_stock',(-2.30,.08,-2.56))
    for x in (-.28,.28):box_prop((x,.16,0),(.39,.40,.50))
    for i in range(2):tin((-.35+i*.30,1.015,.04),['blue','metal','red'][i],.104,.23+.025*i)
    box_prop((.31,1.015,0),(.34,.22,.34))
    hat((.26,2.01,.03),scale=.90)
    shelf_unit('right_low_shelf',(2.25,.08,-2.50),1.62,.91,.59)
    begin('right_shelf_stock',(2.25,.08,-2.50))
    for x in (-.50,0,.50):box_prop((x,.16,0),(.40,.19,.43))
    for i in range(5):tin((-.59+i*.29,.50,.03),['blue','panel','yellow','metal','blue'][i],.105,.19)
    begin('model_sailboat',(1.76,1.03,-2.54))
    prism('Boat curved miniature hull',[(-.34,0),(-.25,.14),(.22,.13),(.39,0),(.22,-.13),(-.25,-.13)],.025,.15,'oak',.027)
    tube('Boat azure hull stripe',[(-.32,.09,.055),(-.23,.09,.145),(.22,.09,.14),(.37,.09,0)],.011,'blue',6)
    tube('Boat mast',[(0,.13,0),(0,.71,0)],.015,'oak_edge',8)
    mesh('Ivory large sail',[(.018,.65,.008),(.018,.20,.008),(.29,.20,.008)],[(0,1,2)],'ivory').modifiers.new('Sail thickness','SOLIDIFY').thickness=.008
    mesh('Rosy small sail',[(-.03,.57,0),(-.28,.22,0),(-.03,.22,0)],[(0,1,2)],'cream').modifiers.new('Sail thickness','SOLIDIFY').thickness=.008
    mesh('Tiny rust pennant',[(0,.71,.005),(.13,.68,.005),(0,.65,.005)],[(0,1,2)],'red').modifiers.new('Pennant thickness','SOLIDIFY').thickness=.006
    begin('yellow_boots',(2.61,1.03,-2.59))
    for x in (-.125,.125):
        lathe('Open yellow boot shaft',(x,.08,0),[(0,.083),(.25,.077),(.28,.095),(.29,.095),(.29,.073),(.09,.064)],'yellow',16)
        ellipsoid('Rounded yellow boot toe',(x,.075,.067),(.17,.15,.30),'yellow',20,12)
        lathe('Boot mouth dark inside',(x,.19,0),[(0,.064),(.004,.064)],'cork',12)

def fish_flat(at=(0,0,0),width=.4,color='ivory',chalk=False):
    x,y,z=at
    points=[(-.44,0),(-.31,.17),(-.03,.20),(.24,.06),(.43,.22),(.37,0),(.43,-.22),(.24,-.06),(-.03,-.16),(-.31,-.12),(-.44,0)]
    pts=[(x+a*width,y+b*width,z) for a,b in points]
    if chalk:tube('Chalk fish contour',pts,.006,'ivory',4)
    else:
        obj=mesh('Carved fish silhouette',pts[:-1],[tuple(range(len(pts)-1))],color)
        obj.modifiers.new('Raised fish relief','SOLIDIFY').thickness=.026
        bevel(obj,.01)
    disc('Fish eye',(x-width*.28,y+width*.025,z+.019),width*.018,.007,'ivory' if chalk else 'oak_dark',8)
    tube('Fish gill',[(x-width*.14,y+width*.09,z+.02),(x-width*.10,y,z+.024),(x-width*.14,y-width*.07,z+.02)],.005,'ivory' if chalk else 'oak_edge',4)

def wall_decor():
    begin('blue_map',(-.48,2.14,-2.915))
    cube('Blue nautical chart',(0,0,0),(1.23,1.05,.035),'6AABBF',.012)
    for x in (-.65,.65):cube('Chart upright frame',(x,0,.02),(.065,1.15,.07),'oak',.014)
    for y in (-.565,.565):cube('Chart cross frame',(0,y,.02),(1.36,.065,.07),'oak_light',.014)
    islands=[[(-.43,.24),(-.36,.41),(-.12,.31),(.04,.41),(.20,.25),(.10,.05),(.24,-.11),(.06,-.33),(-.12,-.40),(-.21,-.18),(-.38,-.09),(-.29,.07)],
             [(.32,.19),(.49,.27),(.51,.11),(.39,-.03)], [(-.47,-.30),(-.40,-.36),(-.47,-.44)]]
    for points in islands:
        face_front(mesh('Chart golden shoreline',[(x,y,.026) for x,y in points],[tuple(range(len(points)))],'DCC180'))
        cx=sum(x for x,y in points)/len(points);cy=sum(y for x,y in points)/len(points)
        face_front(mesh('Chart green land',[(cx+(x-cx)*.81,cy+(y-cy)*.88,.032) for x,y in points],[tuple(range(len(points)))],'8AA373'))
    ring('Chart compass',(.40,-.34,.04),.10,.006,'red',segments=24,sides=4)
    for a in (0,math.pi/2,math.pi/4,math.pi*3/4):tube('Chart compass spoke',[(.40-.11*math.cos(a),-.34-.11*math.sin(a),.04),(.40+.11*math.cos(a),-.34+.11*math.sin(a),.04)],.005,'red',4)
    begin('fish_board',(.69,1.99,-2.91))
    cube('Fish board dark slate',(0,0,0),(.58,.94,.045),'dark',.014)
    for x in (-.32,.32):cube('Fish board wood side',(x,0,.018),(.055,1.02,.065),'oak',.012)
    for y in (-.50,.50):cube('Fish board wood edge',(0,y,.018),(.69,.055,.065),'oak_light',.012)
    fish_flat((0,.26,.033),.46,chalk=True);fish_flat((0,.015,.033),.42,chalk=True)
    for i,w in enumerate([.30,.24,.34]):tube('Fish board chalk water mark',[(-.17,-.20-.07*i,.033),(-.17+w,-.20-.07*i,.033)],.004,'ivory',4)
    begin('hat_rail',(2.12,2.04,-2.875))
    cube('Two hat wooden hook board',(0,0,0),(1.36,.30,.075),'oak',.024)
    for x,col in [(-.34,'oak_light'),(.34,'yellow')]:
        tube('Hat hook',[(x,.02,.04),(x,.03,.17),(x,.10,.18)],.016,'metal',8)
        start_index=len(p.b.CURRENT['objects']);hat((0,0,0),col,1.04)
        transform=Matrix.Translation(v((x,.02,.18)))@Matrix.Rotation(math.pi/2,4,'X')
        for o in p.b.CURRENT['objects'][start_index:]:o.matrix_basis=transform@o.matrix_basis
    begin('wall_hook_bar',(-.25,2.92,-2.89))
    tube('Upper wooden hook rod',[(-.62,0,0),(.62,0,0)],.035,'oak',12)
    for x in (-.58,.58):cube('Hook bar wall bracket',(x,-.015,-.025),(.055,.12,.11),'oak_edge',.01)
    begin('fish_sign',(-3.10,2.17,1.29),90)
    cube('Blank fish sign mounting board',(0,0,0),(.95,.39,.07),'oak_edge',.035)
    fish_flat((0,.015,.055),.87,'ivory')
    begin('bunting',(-3.075,1.87,1.34),90)
    points=[(-.72,.12,0),(-.36,-.03,.01),(0,-.10,.02),(.36,-.03,.01),(.72,.13,0)]
    tube('Soft sagging bunting cord',points,.008,'rope',6)
    for i,col in enumerate(['red','blue','yellow','749563']):
        x=-.53+i*.35;y=-.10+abs(x)*.22
        mesh('Colorful triangular flag',[(x-.12,y+.05,.015),(x+.12,y+.05,.015),(x-.025,y-.23,.025)],[(0,1,2)],col).modifiers.new('Flag thickness','SOLIDIFY').thickness=.007

def fish_bowl():
    begin('counter_square_tool',(-.70,1.20,-1.12))
    cube('Grey square instrument base',(0,.075,0),(.32,.15,.27),'metal',.017)
    cube('Grey stepped instrument top',(-.025,.20,-.03),(.24,.12,.19),'metal_light',.018)
    cube('Instrument thin drawer seam',(0,.072,.14),(.28,.007,.005),'dark',0)
    cube('Instrument small brass pull',(0,.09,.148),(.06,.014,.01),'brass',.003)
    begin('fishbowl_contents',(.33,1.20,-1.03))
    lathe('Fishbowl pale sand base',(0,0,0),[(0,.16),(.045,.23),(.085,.25)],'ivory',32)
    for i in range(12):
        a=i*2.399;r=.16*math.sqrt((i+1)/12)
        ellipsoid('Bowl round pastel pebble',(r*math.cos(a),.08+.014*(i%3),r*math.sin(a)),(.075,.055,.07),['panel','cream','D0ADB0','A4ADA3'][i%4],10,6)
    for i in range(3):
        x=.13+i*.026
        leaf('Aquarium long leaf',(x,.09,-.08),(x+.035*(i-1),.34+.06*(i%2),-.09),.025,'799A69')
    for x,y,z,col,flip in [(-.10,.25,.055,'red',False),(.10,.31,-.01,'yellow',True)]:
        ellipsoid('Small fish body',(x,y,z),(.19,.11,.075),col,16,10)
        sign=-1 if flip else 1
        mesh('Small fish fan tail',[(x+sign*.07,y,z),(x+sign*.15,y+.055,z),(x+sign*.15,y-.055,z)],[(0,1,2)],col).modifiers.new('Tail thickness','SOLIDIFY').thickness=.009
        ellipsoid('Fish ivory eye',(x-sign*.055,y+.019,z+.036),(.028,.028,.013),'ivory',10,6)
        ellipsoid('Fish dark pupil',(x-sign*.057,y+.020,z+.045),(.012,.012,.008),'dark',8,6)
    begin('fishbowl_glass',(.33,1.20,-1.03))
    lathe('Open round aquarium glass',(0,0,0),[(.015,.16),(.06,.23),(.18,.29),(.32,.28),(.43,.21),(.46,.20),(.46,.19),(.43,.20),(.32,.27),(.18,.28),(.06,.22),(.027,.16)],'DDEBF0',48)
    begin('fishbowl_glints',(.33,1.20,-1.03))
    ring('Aquarium open rim',(0,.46,0),.20,.009,'ivory','xz',48)
    tube('Aquarium left soft glint',[(-.22,.15,.15),(-.25,.24,.13),(-.22,.33,.13)],.010,'EAF0E9',6)
    tube('Aquarium right soft glint',[(.22,.25,.15),(.20,.34,.14)],.008,'EAF0E9',6)

def anchor_rug():
    begin('anchor_rug',(0,.08,.83))
    o=cylinder('Deep blue circular rug with baked woven anchor',(0,.013,0),.95,.026,'navy',vertices=80)
    # Original mathematical textile artwork, baked into the single room atlas.
    # Keep dense braids off the runtime mesh and avoid subpixel UV islands.
    n=1024;yy,xx=np.mgrid[0:n,0:n];x=(xx+.5)/n*1.9-.95;z=(yy+.5)/n*1.9-.95
    r=np.sqrt(x*x+z*z);angle=np.arctan2(z,x)
    image=np.ones((n,n,4),dtype=np.float32)
    weave=.96+.035*np.cos(r*math.tau/.018+np.sin(angle*90)*.6)
    image[:,:,:3]=np.array(rgb('navy'))[None,None,:]*weave[:,:,None]
    ink=(abs(r-.82)<.009)|(abs(r-.87)<.009)|(abs(np.sqrt(x*x+(z+.35)**2)-.075)<.025)
    def stroke(a,b,width):
        ax,az=a;bx,bz=b;dx=bx-ax;dz=bz-az
        t=np.clip(((x-ax)*dx+(z-az)*dz)/(dx*dx+dz*dz),0,1)
        return (x-ax-t*dx)**2+(z-az-t*dz)**2<width*width
    ink |= stroke((0,-.29),(0,.33),.027)|stroke((-.19,-.16),(.19,-.16),.026)
    pts=[(-.34,.14),(-.29,.27),(-.16,.36),(0,.39),(.16,.36),(.29,.27),(.34,.14)]
    for a,b in zip(pts,pts[1:]):ink |= stroke(a,b,.028)
    for side in (-1,1):
        ink |= stroke((side*.34,.14),(side*.24,.21),.023)|stroke((side*.34,.14),(side*.37,.25),.023)
    image[ink,:3]=np.array(rgb('ivory'))[None,:]*weave[ink,None]
    tex=bpy.data.images.new('Tackle original woven anchor artwork',width=n,height=n,alpha=True)
    tex.colorspace_settings.name='Non-Color';tex.pixels.foreach_set(image.ravel());tex.pack()
    mat=material('navy','cloth').copy();mat.name='Tackle_Rug_Painted_Source'
    nt=mat.node_tree;node=nt.nodes.new('ShaderNodeTexImage');node.image=tex
    uvnode=nt.nodes.new('ShaderNodeUVMap');uvnode.uv_map='RugArtwork'
    nt.links.new(uvnode.outputs['UV'],node.inputs['Vector'])
    nt.links.new(node.outputs['Color'],nt.nodes.get('Principled BSDF').inputs['Base Color'])
    layer=o.data.uv_layers.new(name='RugArtwork')
    for f in o.data.polygons:
        for li in f.loop_indices:
            vertex=o.data.vertices[o.data.loops[li].vertex_index].co
            layer.data[li].uv=((vertex.x/.95+1)/2,(-vertex.y/.95+1)/2)
    o.data.materials.clear();o.data.materials.append(mat)
    for i in range(48):
        a=math.tau*i/48
        for da in (-.012,.012):tube('Short rug fringe',[(.95*math.cos(a+da),.02,.95*math.sin(a+da)),(1.015*math.cos(a+da),.012,1.015*math.sin(a+da))],.007,'rope',4)

def net_shape(width=.76,height=.95):
    # Explicit diamond net draped over a sloping invisible support shape.
    def pt(u,vv):
        return (u*width,(1-vv)*height,.12+.45*vv+.06*math.sin(u*7+vv*5))
    for sign in (-1,1):
        for k in range(-6,10):
            pts=[]
            for j in range(13):
                vv=j/12;u=k*.14+sign*vv*.68-.5
                if -.5<=u<=.5:pts.append(pt(u,vv))
            if len(pts)>1:tube('Diamond fishing net cord',pts,.008,'rope',5)
    tube('Fishing net top rope',[pt(-.5,0),pt(0,0),pt(.5,0)],.015,'rope',6)

def kai_rafa():
    begin('kai_oar_barrel',(-2.65,.08,2.19),collision=[{'at':[0,.31,0],'size':[.54,.62,.54]}])
    barrel_low('Oar barrel',.28,.62,14)
    for i in range(3):
        x=-.12+i*.12
        tube('Oar long shaft',[(x,.18,0),(x+(i-1)*.13,1.06,-.02)],.023,'oak_light',8)
        o=cube('Oar broad rounded paddle',(x+(i-1)*.17,1.18,-.02),(.14,.46,.045),'oak_light',.06)
        o.rotation_euler.y=(i-1)*.18
    begin('kai_stool',(-1.99,.08,2.23),collision=[{'at':[0,.31,0],'size':[.48,.62,.48]}])
    cylinder('Kai round wood stool seat',(0,.575,0),.25,.09,'oak_light',vertices=32)
    for a in (0,math.tau/3,math.tau*2/3):tube('Kai stool splayed leg',[(.20*math.cos(a),.0035,.20*math.sin(a)),(.15*math.cos(a),.56,.15*math.sin(a))],.037,'oak',8)
    begin('kai_fishing_net',(-2.79,.09,1.03),yaw=0)
    net_shape(.60,.82)
    begin('rafa_fishing_net',(2.95,.09,-.90),yaw=0)
    net_shape(.45,.73)

def shared_plant(name,original,at,scale=1):
    path=p.ROOT/'assets/rooms/_shared/plants/source/plants.blend'
    with bpy.data.libraries.load(str(path),link=False) as (src,dst):dst.collections=['KIT_'+original]
    c=dst.collections[0];bpy.context.scene.collection.children.link(c)
    root=next(o for o in c.objects if o.type=='EMPTY');root.location=v(at);root.rotation_euler=(0,0,0);root.scale=(1,1,1)
    c.name='KIT_'+name;root.name=name
    objects=[o for o in c.objects if o.type=='MESH']
    for o in objects:
        leaf_like=any(word in o.name.lower() for word in ('leaf','crown','spathe','stem','vine'))
        o.data=o.data.copy();o.data.materials.clear()
        o.data.transform(Matrix.Diagonal(Vector((scale,scale,scale,1)))@o.matrix_basis);o.matrix_basis=Matrix.Identity(4)
        if original=='pothos' and leaf_like:
            # Let the existing library vines drape over the front shelf lip.
            for vertex in o.data.vertices:
                t=max(0,min(1,(.22-vertex.co.z)/.22))
                vertex.co.y=-max(-vertex.co.y,.245*t)
        color=('76935D' if 'stem' in o.name.lower() else '88A66D') if leaf_like else 'terra'
        o.data.materials.append(material(color))
        if leaf_like and any(len(f.vertices)>2 for f in o.data.polygons):
            m=o.modifiers.new('Two sided library leaf','SOLIDIFY');m.thickness=.0008
        o['source_library']=str(path.relative_to(p.ROOT));o['source_module']=original
    p.KITS[name]={'collection':c,'root':root,'objects':objects,'at':list(at),'yaw':0,'collision':[]}

def anchors_and_bench():
    entries=[
        ('use_counter',[-.36,1.20,-.85],'curved_counter',0),
        ('stand_counter',[-.36,.08,-.02],'curved_counter',0),
        ('npc_keeper',[-.36,.08,-2.35],'curved_counter',180),
        ('badge_keeper',[-.36,1.98,-2.35],'curved_counter',180),
        ('stand_keeper',[-.36,.08,-.02],'curved_counter',0),
        ('npc_kai',[-1.85,.08,1.55],'kai_stool',135),
        ('stand_kai',[-1.10,.08,1.10],'kai_stool',-90),
        ('npc_rafa',[1.85,.08,-1.55],'rafa_float_barrel',225),
        ('stand_rafa',[1.30,.08,-.85],'rafa_float_barrel',90),
        ('use_fish_board',[.69,1.99,-2.86],'fish_board',0),
        ('stand_fish_board',[.96,.08,-2.07],'fish_board',0),
        ('spawn',[0,.08,.83],'room_shell',0),
        ('exit',[0,.08,3.40],'room_shell',180),
        ('badge_exit',[0,.30,3.20],'room_shell',180),
        ('sign_name',[-3.02,2.07,1.29],'fish_sign',90),
    ]
    anchors=[dict(name=n,position=at,module=mod,yaw_degrees=yaw) for n,at,mod,yaw in entries]
    anchors[-1]['size']=[.72,.12]
    for entry in anchors:
        o=bpy.data.objects.new(entry['name'],None);bpy.context.scene.collection.objects.link(o)
        o.location=v(entry['position']);o.empty_display_size=.12;o['purpose']='suggested gameplay anchor; engineer owns integration'
    p.MANIFEST_EXTRA.update({'anchors':anchors,'spawn':[0,.09,.83],
        'review_contract':{'game_view':{'resolution':[360,800],'pitch':43,'yaw':45,'orthographic_width_m':6.72},
          'whole_room':{'pitch':43,'yaw':45,'orthographic_width_m':10.2},
          'framing_decision':'上官婉儿确认：6.72 m 游戏取景与完整房间全景两张分别验收；保留房间尺寸。'},
        'floor_size':[6.8,6.4],'floor_y':.08,
        'bench':{'floor_y':.08,'route':[
          {'name':'central anchor rug','position':[0,.08,.83],'capture':'main'},
          {'name':'counter approach','position':[-.36,.08,-.02]},
          {'name':'counter right aisle','position':[1.05,.08,-.40]},
          {'name':'fish board approach','position':[.96,.08,-2.07]},
          {'name':'return to public aisle','position':[1.30,.08,-.32]},
          {'name':'Rafa approach','position':[1.30,.08,-.85]},
          {'name':'Old Kai approach','position':[-1.10,.08,1.10]},
          {'name':'open front exit','position':[0,.08,2.83],'capture':'door'}],
          'blocked':[
            {'name':'curved counter','from':[-.36,.09,-.02],'to':[-.36,.09,-1.16],'target':'curved_counter'},
            {'name':'right shelf','from':[2.25,.09,-1.65],'to':[2.25,.09,-2.50],'target':'right_low_shelf'},
            {'name':'rod rack','from':[-2.15,.09,.17],'to':[-2.92,.09,.17],'target':'rod_rack'},
            {'name':'left wall','from':[-2.7,.09,-1.45],'to':[-3.8,.09,-1.45],'target':'room_shell'},
            {'name':'right floor edge','from':[2.75,.09,.0],'to':[3.8,.09,0],'target':'room_shell'},
            {'name':'front floor edge','from':[1.5,.09,2.6],'to':[1.5,.09,3.7],'target':'room_shell'}],
          'gaps':[{'name':'keeper clear aisle','from':[-.75,.09,-2.22],'to':[.75,.09,-2.22],
                   'measure':[[-.36,.73,-2.96],[-.36,.73,-1.60]],'minimum':.70,'width':1.36}],
          'entrance':{'inside':[0,.09,2.7],'outside':[0,.09,3.47]},
          'slide':{'from':[2.90,.09,-.30],'direction':[1,0,.8],'tangent':[0,0,1],'seconds':.55},
          'input_start':[0,.09,1.7],
          'scale':{'door':{'applicable':False,'reason':'Open front diorama exit; no door in approved Stark design.'},
                   'counter':{'height':1.12,'source':'Curved worktop top minus floor'},
                   'chair':{'height':.62,'source':'Kai stool seat top minus floor'},
                   'table':{'applicable':False,'reason':'Only retail shelves, no table in the approved room.'}}}})

def build():
    start('tackle_shop','2681:135486');p.QA=p.ROOT/'output/tackle-214'
    p.b.PALETTE.update(PALETTE)
    p.BAKE_SETTINGS.update(ao_distance=.35,ao_strength=.35,floor_ao_strength=.24)
    architecture();porthole();counter();lamps();rod_rack();shelves();wall_decor();fish_bowl();anchor_rug();kai_rafa()
    shared_plant('shelf_pothos','pothos',(-2.64,2.09,-2.40),.78)
    shared_plant('rafa_plant','peace_lily',(2.98,.08,.32),.74)
    shared_plant('shelf_small_plant','peace_lily',(2.97,1.04,-2.40),.22)
    anchors_and_bench()
    target=[0,1.15,0];distance=20;pitch=math.radians(43);yaw=math.pi/4
    camera={'position':[target[0]+distance*math.cos(pitch)*math.sin(yaw),target[1]+distance*math.sin(pitch),target[2]+distance*math.cos(pitch)*math.cos(yaw)],'target':target,'size':11.4}
    lighting={'background':'EAD5C8','ambient_color':'FFF7F3','ambient':.52,'sun_color':'FFF3EA','sun':.72,
              'sun_position':[-3,8,5],'sun_target':[0,0,0],'shadow_bias':.3,'shadow_normal_bias':2.0,'shadow_distance':25,'points':[]}
    finalize(camera,lighting)
    layout=json.loads((p.OUT/'layout.json').read_text())
    for row in layout['assets']:
        row['material']='glass' if row['name']=='fishbowl_glass' else 'plain'
        row['cast_shadow']=row['name'] not in ('porthole_view','fishbowl_glass','fishbowl_glints','shelf_pothos','rafa_plant','shelf_small_plant','bunting')
    (p.OUT/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n')
    # Very thin geometry needs guarded color tiles instead of subpixel UV islands.
    # Preserve source semantic colors before the bake merges modules/materials.
    detail_modules={'rod_rack','float_barrel','kai_oar_barrel','kai_fishing_net','rafa_fishing_net',
                    'shelf_pothos','rafa_plant','shelf_small_plant','bunting','counter_ship_wheel',
                    'fishbowl_glints','fish_board'}
    color_vertices={}
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
    for name,kit in p.KITS.items():
        if name not in detail_modules and name!='anchor_rug':continue
        table={};inv=kit['root'].matrix_world.inverted()
        for obj in kit['objects']:
            if name=='anchor_rug' and not obj.name.startswith('Short rug fringe'):continue
            rgb_linear=obj.data.materials[0].diffuse_color[:3]
            encoded=[round(255*(12.92*c if c<=.0031308 else 1.055*c**(1/2.4)-.055)) for c in rgb_linear]
            data=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),depsgraph=deps)
            transform=inv@obj.matrix_world
            for vertex in data.vertices:
                q=transform@vertex.co
                key=','.join(f'{value:.4f}' for value in (q.x,q.z,-q.y))
                values=table.setdefault(key,[])
                if encoded not in values:values.append(encoded)
            bpy.data.meshes.remove(data)
        color_vertices[name]={'complete':name in detail_modules,'vertices':table}
    (p.QA/'source-detail-colors.json').write_text(json.dumps(color_vertices))
    complete()
    if '--geometry-only' not in sys.argv:
        subprocess.run([shutil.which('python3'),str(p.ROOT/'tools/art/finalize_tackle_atlas.py')],check=True)
        stats=json.loads((p.OUT/'asset_stats.json').read_text())
        stats['rod_rack_with_barrel_triangles']=sum(a['triangles'] for a in stats['assets'] if a['name'] in ('rod_rack','float_barrel'))
        stats['plant_budget_triangles']=sum(a['triangles'] for a in stats['assets'] if a['name'] in ('shelf_pothos','rafa_plant','shelf_small_plant'))
        stats['materials']=2;stats['budget_limits']={'placed_triangles':200000,'static_surfaces':60,'rod_rack_and_barrel':1200}
        stats['budget_passed']=stats['scene_triangles']<=200000 and stats['static_draw_surfaces']<=60 and stats['rod_rack_with_barrel_triangles']<=1200
        (p.OUT/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
        print('TACKLE_BUDGET',stats['scene_triangles'],stats['static_draw_surfaces'],stats['rod_rack_with_barrel_triangles'],flush=True)
        assert stats['budget_passed'], 'Tackle room or rod-rack budget exceeded'

if __name__=='__main__':build()
