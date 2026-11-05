"""Temporary modular contracts for Zhao Yun / Huang Zhong. No final art is claimed."""
import math

REPEATED=['alc_bench','alc_lamp','alc_rail_straight','alc_rail_corner','alc_curb','alc_tree_a','alc_tree_b','alc_flowerbed','alc_bin','alc_sign']
OWNERS={name:'赵云' for name in REPEATED}
OWNERS.update({n:'黄忠' for n in ['alc_lighthouse','alc_lighthouse_far','alc_watertower','alc_watertower_far','alc_museum_far',
 'alc_far_bridge','alc_far_bridge_far','alc_far_city','alc_far_city_far','alc_far_hills','alc_far_hills_far']})


def build(kit,box,prism,place):
    kit.begin('alc_museum_far',ao=False)
    box('museum_far_placeholder',(0,4.5,0),(40,9,10),'building',0)
    for name,size,pos in [('alc_lighthouse',(3.7,15,3.7),(-25,10,-11.5)),('alc_watertower',(5.4,12,5.4),(25,10,-14))]:
        for suffix in ['', '_far']:
            kit.begin(name+suffix,ao=False)
            box(name+suffix+'_placeholder',(0,size[1]/2,0),size,'building' if 'lighthouse' in name else 'wood',0)
        place(name,pos,'SummitZone')
    kit.begin('alc_bench',ao=False)
    box('seat',(0,.395,0),(1.5,.11,.48),'wood',0)
    box('back',(0,.73,-.21),(1.5,.56,.10),'wood',0)
    for x in [-.55,.55]:box('support',(x,.17,0),(.10,.34,.40),'dark',0)
    kit.begin('alc_lamp',ao=False)
    box('post',(0,1.6,0),(.12,3.2,.12),'dark',0)
    box('light',(0,3.35,0),(.3,.3,.3),'bird',0)
    kit.begin('alc_rail_straight',ao=False)
    box('rail',(0,.95,0),(2,.10,.10),'stone',0)
    for x in [-.95,.95]:box('post',(x,.5,0),(.10,1,.10),'stone',0)
    kit.begin('alc_rail_corner',ao=False)
    box('corner_post',(0,.5,0),(.14,1,.14),'stone',0)
    box('arm_x',(.25,.95,0),(.5,.1,.1),'stone',0)
    box('arm_z',(0,.95,.25),(.1,.1,.5),'stone',0)
    kit.begin('alc_curb',ao=False)
    box('curb',(0,.08,0),(2,.16,.18),'stone',0)
    for name,h,w in [('alc_tree_a',3.4,1.8),('alc_tree_b',4.0,2.2)]:
        kit.begin(name,ao=False)
        box('trunk',(0,.7,0),(.25,1.4,.25),'wood',0)
        box('crown',(0,(h+1.4)/2,0),(w,h-1.4,w),'garden',.03)
    kit.begin('alc_flowerbed',ao=False)
    box('planter',(0,.2,0),(1.4,.4,.7),'stone',0)
    box('flowers_placeholder',(0,.475,0),(1.25,.15,.55),'garden',0)
    kit.begin('alc_bin',ao=False)
    box('bin',(0,.375,0),(.45,.75,.45),'wood',0)
    kit.begin('alc_sign',ao=False)
    box('post',(0,.65,0),(.12,1.3,.12),'wood',0)
    box('board',(0,1.45,0),(.9,.45,.12),'building',0)
    # Flat colored silhouettes, not completed scenery assets. Front +Z, bottom-centre pivot.
    def rect(n,x,y,w,h,c):
        kit.mesh(n,[(x-w/2,y,0),(x+w/2,y,0),(x+w/2,y+h,0),(x-w/2,y+h,0)],[(0,1,2,3)],c)
    for suffix in ['', '_far']:
        kit.begin('alc_far_bridge'+suffix,ao=False)
        rect('deck',0,.18,2,.06,'bridge')
        for x in [-.55,.55]:rect('tower',x,0,.065,.9,'bridge')
        count=16 if not suffix else 8
        def cable_height(x):return .31+.52*(abs(x)/.55)**2 if abs(x)<.55 else .83-(abs(x)-.55)*1.25
        points=[(-1+i*2/count,cable_height(-1+i*2/count)) for i in range(count+1)]
        for (x0,y0),(x1,y1) in zip(points,points[1:]):
            kit.mesh('continuous_cable',[(x0,y0-.014,0),(x1,y1-.014,0),(x1,y1+.014,0),(x0,y0+.014,0)],[(0,1,2,3)],'bridge')
        for i in range(count):
            x=-1+(i+.5)*2/count;y=cable_height(x)
            rect('hanger',x,.24,.012,y-.24,'bridge')
        kit.begin('alc_far_city'+suffix,ao=False)
        for i in range(12 if not suffix else 6):
            count2=12 if not suffix else 6;x=-2.4+(i+.5)*4.8/count2
            rect('skyline',x,0,4.8/count2*.85,.35+(i%5)*.14,'far')
        kit.begin('alc_far_hills'+suffix,ao=False)
        n=12 if not suffix else 6
        v=[(-4,0,0),(4,0,0)]+[(4-i*8/n,.2+.35*math.sin(i*math.pi/n)+.1*math.sin(i*math.pi*3/n),0) for i in range(n+1)]
        kit.mesh('hills',v,[tuple(range(len(v)))],'garden')


def scatter(place):
    # One easily replaceable focal prop every <= 6 m on each horizontal terrace.
    patterns=[['alc_flowerbed','alc_sign','alc_tree_a','alc_bench','alc_bin','alc_lamp'],
              ['alc_lamp','alc_flowerbed','alc_tree_b','alc_sign','alc_bench','alc_flowerbed'],
              ['alc_tree_a','alc_bin','alc_flowerbed','alc_bench','alc_sign','alc_lamp']]
    for row,(y,z) in enumerate([(3.25,7.5),(5.5,3),(7.75,-1.5)]):
        for i,x in enumerate([-21,-15,-9,-3,3,7]):
            asset=patterns[row][i]
            # Trees/planters stand just beyond the upper rail; seats stay on the paving edge.
            pz=z-2.1 if asset in ['alc_tree_a','alc_tree_b','alc_flowerbed'] else z-.9
            place(asset,(x,y,pz),'TerraceZone',collision=True)
    for asset,p in [('alc_sign',(-18.4,1,11.0)),('alc_bench',(-19,1,13.4)),('alc_flowerbed',(-18.7,1,10.3))]:place(asset,p,'DockZone')
    for i,x in enumerate([-24,-18,-12,-6,0,6,12,18,24]):
        place(['alc_flowerbed','alc_bench','alc_lamp'][i%3],(x,10,-5.05),'SummitZone')
    for p,z in [((-23.5,1,14),'DockZone'),((-23.5,1,19.5),'DockZone'),((-27.8,10,-4.7),'SummitZone'),((27.8,10,-4.7),'SummitZone')]:
        place('alc_rail_corner',p,z,collision=False)


def rail_instances(edges,place):
    # Combine adjacent stair edges into sloped runs. A shear keeps uprights vertical.
    lines={}
    for (zone,axis,fixed,y),spans in edges.items():
        lines.setdefault((zone,axis,fixed),[]).extend((a,b,y) for a,b in spans)
    for (zone,axis,fixed),spans in lines.items():
        spans.sort();runs=[]
        for a,b,y in spans:
            if runs and abs(runs[-1][-1][1]-a)<.001:
                last=runs[-1][-1];slope=(y-last[2])/((a+b-last[0]-last[1])/2)
                old_slope=0 if len(runs[-1])<2 else (last[2]-runs[-1][-2][2])/((last[0]+last[1]-runs[-1][-2][0]-runs[-1][-2][1])/2)
                if abs(slope-old_slope)<.01 or len(runs[-1])==1:
                    if abs(slope)<=.51:runs[-1].append((a,b,y));continue
            runs.append([(a,b,y)])
        for run in runs:
            a=run[0][0];b=run[-1][1]
            slope=0 if len(run)<2 else (run[-1][2]-run[0][2])/((run[-1][0]+run[-1][1]-run[0][0]-run[0][1])/2)
            middle=(a+b)/2;middle_y=run[0][2]+slope*(middle-(run[0][0]+run[0][1])/2)
            pieces=max(1,math.ceil((b-a)/2))
            for i in range(pieces):
                length=(b-a)/pieces;t=a+length*(i+.5);y=middle_y+slope*(t-middle)
                location=(t,y,fixed) if axis=='x' else (fixed,y,t)
                yaw=0 if axis=='x' else -math.pi/2
                for asset in ['alc_rail_straight','alc_curb']:
                    p=place(asset,location,zone,yaw=yaw,scale=[length/2,1,1],collision=asset=='alc_rail_straight')
                    if abs(slope)>.001:
                        p['basis_columns']=[[length/2,length*slope/2,0],[0,1,0],[0,0,1]] if axis=='x' else [[0,length*slope/2,length/2],[0,1,0],[-1,0,0]]
                        p['slope_rise_m']=length*slope
