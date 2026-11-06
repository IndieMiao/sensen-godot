"""Editable island surfaces and public-museum facade, in Godot metres."""
import math
import random
import museum_roof


def cliff(kit, name, polygon, low, high):
    """Three closed rings give the shoreline broad, matte rock facets."""
    rng = random.Random(name)
    if sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(polygon,polygon[1:]+polygon[:1]))>0:
        polygon=list(reversed(polygon))
    outline=[]
    for a,b in zip(polygon,polygon[1:]+polygon[:1]):
        steps=max(1,math.ceil(math.dist(a,b)/2.6))
        outline.extend((a[0]+(b[0]-a[0])*i/steps,a[1]+(b[1]-a[1])*i/steps) for i in range(steps))
    cx=sum(p[0] for p in outline)/len(outline);cz=sum(p[1] for p in outline)/len(outline)
    n=len(outline);vertices=[]
    for ring in range(3):
        for x,z in outline:
            inset=rng.uniform(.15,.55) if ring==1 else .10 if ring==0 else 0
            d=max(.1,math.hypot(x-cx,z-cz))
            y=low if ring==0 else high if ring==2 else low+(high-low)*rng.uniform(.35,.60)
            vertices.append((x-(x-cx)/d*inset,y,z-(z-cz)/d*inset))
    faces=[tuple(reversed(range(n))),tuple(range(2*n,3*n))]
    for ring in range(2):
        for i in range(n):
            a=ring*n+i;b=ring*n+(i+1)%n;c=b+n;d=a+n
            faces.extend([(a,b,c),(a,c,d)])
    obj=kit.mesh(name,vertices,faces,'rock')
    for color in ['rock_light','rock_shadow','rock_warm']:
        obj.data.materials.append(kit.mats[color])
    for face in obj.data.polygons:
        face.material_index=rng.choices([0,1,2,3],[5,3,1,2])[0]
    return obj


def garden_patch(kit,name,x,y,z,rx,rz,color):
    rng=random.Random(name);points=[]
    for i in range(12):
        angle=i*math.tau/12;r=rng.uniform(.86,1.0)
        points.append((x+math.cos(angle)*rx*r,y+.008,z+math.sin(angle)*rz*r))
    # X/Z clockwise gives an upward Godot normal.
    return kit.mesh(name,points,[tuple(reversed(range(12)))],color)


def masonry(kit,box,name,x0,x1,z,low,high):
    """Shallow dressed-stone courses on the visible front retaining wall."""
    rng=random.Random(name);course=.55
    for row in range(max(1,math.ceil((high-low)/course))):
        bottom=low+row*course;top=min(high,bottom+course)
        x=x0-(.8 if row%2 else 0)
        while x<x1:
            end=min(x1,x+1.6);start=max(x0,x)
            if end-start>.10:
                lo=start+.0125;hi=end-.0125;yb=bottom+.0125;yt=top-.0125
                kit.mesh(name+'_course_%02d'%row,[(lo,yb,z+.027),(hi,yb,z+.027),(hi,yt,z+.027),(lo,yt,z+.027)],
                    [(0,1,2,3)],rng.choice(['stone','stone','stone_light','stone_shade']))
            x+=1.6


def stair_flight(kit,flight,x0,x1,z0,z1,high,low):
    """Real 0.15 m risers; closed shared sides avoid buried cube faces per tread."""
    run=(z1-z0)/15;bottom=low-.2
    profile=[(bottom,z0),(high+.02,z0)]
    for i in range(15):
        y=high-i*.15+.02;front=z0+(i+1)*run;back=front-run
        obj=kit.mesh('flight_%d_riser_%02d'%(flight,i),
            [(x0,y,back),(x0,y,front),(x1,y,front),(x1,y,back),
             (x0,y-.15,front),(x1,y-.15,front)],[(0,1,2,3),(4,5,2,1)],'road')
        obj.data.materials.append(kit.mats['stone_light']);obj.data.polygons[1].material_index=1
        profile.extend([(y,front),(y-.15,front)])
    profile.append((bottom,z1))
    n=len(profile)
    kit.mesh('flight_%d_solid_sides'%flight,[(x,y,z) for x in [x0,x1] for y,z in profile],
        [tuple(reversed(range(n))),tuple(range(n,2*n))],'stone')
    kit.mesh('flight_%d_closed_base'%flight,
        [(x0,bottom,z0),(x1,bottom,z0),(x1,bottom,z1),(x0,bottom,z1),
         (x0,high+.02,z0),(x1,high+.02,z0),(x0,low+.02,z1),(x1,low+.02,z1)],
        [(0,1,2,3),(0,4,5,1),(3,2,7,6)],'stone')


def _arch(width,height,steps=10):
    radius=width/2;spring=height-radius
    return [(-radius,0),(radius,0)]+[(radius*math.cos(i*math.pi/steps),spring+radius*math.sin(i*math.pi/steps)) for i in range(steps+1)]


def museum_sign_icon(kit,front=5.195):
    """Language-neutral lighthouse silhouette; all shapes are editable geometry."""
    shapes=[('tower',[(-.13,-.18),(.13,-.18),(.09,.07),(-.09,.07)]),
            ('lantern',[(-.12,.09),(.12,.09),(.12,.18),(-.12,.18)]),
            ('roof',[(-.17,.20),(.17,.20),(0,.28)]),
            ('island_base',[(-.36,-.25),(.36,-.25),(.25,-.21),(-.25,-.21)])]
    for name,points in shapes:
        kit.mesh('museum_pictogram_'+name,[(x,4.12+y,front) for x,y in points],
                 [tuple(range(len(points)))],'sign_cream')


def museum(kit,box):
    kit.begin('alc_museum',ao=False)
    box('public_museum_wall',(0,4.2,0),(39.84,8.4,9.84),'building',.04)
    box('limestone_plinth',(0,.18,0),(40,.36,10),'stone',.025)
    museum_roof.build(kit,box)
    for y in [.52,4.35,8.15]:box('facade_horizontal_course',(0,y,4.99),(40,.16,.15),'trim',.015)
    for x in [-19.55,-10.2,10.2,19.55]:box('facade_pilaster',(x,4.33,5.0),(.42,7.5,.16),'trim',.025)
    for x in range(-18,19,3):
        for bottom in [1.15,5.15]:
            if x==0 and bottom<2:continue
            outer=_arch(1.55,2.40);inner=[(px,py+.15) for px,py in _arch(1.25,2.10)]
            n=len(outer)
            vertices=[(x+px,bottom+py,5.045) for px,py in outer+inner]
            kit.mesh('limestone_arch_frame',vertices,[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],'trim')
            kit.mesh('unbarred_single_glazing',[(x+px,bottom+py,5.018) for px,py in inner],[tuple(range(n))],'glass')
            box('window_sill',(x,bottom+.06,5.08),(1.66,.12,.24),'trim',.015)
            # A broad reflection, not bars or a grid.
            kit.mesh('glass_soft_reflection',[(x-.48,bottom+.32,5.022),(x+.18,bottom+.32,5.022),(x-.48,bottom+1.7,5.022)],[(0,1,2)],'glass_light')
    # Welcoming double glazing and a language-neutral landmark pictogram.
    for x in [-1.8,1.8]:box('visitor_portal_pier',(x,2.0,5.07),(.55,3.4,.28),'trim',.025)
    box('visitor_portal_lintel',(0,3.75,5.07),(4.45,.30,.28),'trim',.025)
    box('museum_glazed_entry',(0,1.85,5.09),(2.65,3.05,.12),'glass',.01)
    box('entry_door_join',(0,1.85,5.16),(.045,3.05,.025),'dark',0)
    for x in [-.16,.16]:box('entry_pull_handle',(x,1.65,5.20),(.035,.48,.045),'trim',.006)
    box('museum_blank_sign_panel',(0,4.12,5.12),(4.45,.65,.12),'sign_teal',.02)
    museum_sign_icon(kit)
    # Side galleries also read as a public building when the view turns oblique.
    for x in [-19.9,19.9]:
        for z in [-3.15,0,3.15]:
            for y in [2.22,6.22]:
                box('side_gallery_frame',(x,y,z),(.10,2.28,1.40),'trim',.015)
                box('side_gallery_glazing',(x+(.061 if x>0 else -.061),y,z),(.025,1.98,1.10),'glass',0)


def museum_proxy(kit,box):
    """Temporary matching silhouette until Huang Zhong supplies the authored far LOD."""
    kit.begin('alc_museum_far',ao=False)
    box('museum_far_colour_proxy',(0,4.2,0),(40,8.4,10),'building',0)
    box('museum_far_roof',(0,8.45,0),(39.6,.10,9.6),'roof',0)
    for z in [-4.85,4.85]:box('museum_far_parapet',(0,8.70,z),(40,.35,.30),'trim',0)
    for x in [-19.85,19.85]:box('museum_far_parapet_end',(x,8.70,0),(.30,.35,9.4),'trim',0)
    for x in [-15,-7,7,15]:box('museum_far_vent',(x,8.8,-1),(.9,.4,.9),'trim',0)
    for y in [4.35,8.15]:box('museum_far_course',(0,y,5.02),(40,.16,.08),'trim',0)
    for x in range(-18,19,3):
        for bottom in [1.3,5.3]:
            if x==0 and bottom<2:continue
            arch=_arch(1.25,2.1,6)
            kit.mesh('museum_far_unbarred_window',[(x+px,bottom+py,5.025) for px,py in arch],[tuple(range(len(arch)))],'glass')
    box('museum_far_public_door',(0,1.85,5.06),(2.65,3.05,.08),'glass',0)
    box('museum_far_sign',(0,4.12,5.10),(4.45,.65,.08),'sign_teal',0)
    museum_sign_icon(kit,front=5.151)
