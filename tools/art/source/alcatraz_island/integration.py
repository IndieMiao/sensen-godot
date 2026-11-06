"""Island assembly adjustments for the approved reusable prop packs."""
import math
import json
from collections import defaultdict


def collaborator_points(folder,here,placements,place):
    # Replace exactly the 114 original nature slots, preserving their source IDs.
    replacement=json.loads((folder/'alc_nature_placements.json').read_text())['points']
    table={p['source_name']:p for p in replacement};counts=defaultdict(int);used=[]
    for p in placements:
        name='%s_%03d'%(p['asset'],counts[p['asset']]);counts[p['asset']]+=1
        if name not in table:continue
        row=table[name];p.update({k:row[k] for k in ['asset','position','zone','yaw','scale','collision']})
        p['source_name']=name;used.append(name)
    assert len(used)==len(table)==114,(len(used),len(table))
    for rows in [json.loads((folder/'alc_dock_placements.json').read_text())['points'],
                 json.loads((here.parent/'alcatraz_ruins_424/suggested_placements.json').read_text())['instances'],
                 json.loads((folder/'alc_shore_foam_placements.json').read_text())['points']]:
        for row in rows:
            p=place(row['asset'],row['position'],row['zone'],yaw=math.radians(row['rotation_degrees'][1]),scale=row['scale'],collision=False)
            p['source_name']=row['name']
            if 'basis_columns' in row:p['basis_columns']=row['basis_columns']
    # Open the ruined arch view: move the two southern crowns behind its pillars.
    for p in placements:
        if p['asset'].startswith('alc_tree_') and p['position'][1]==3.25:
            if p['position'][0:3]==[18,3.25,6.6]:p['position']=[18,3.25,3.65]
            elif p['position'][0:3]==[21.1,3.25,7]:p['position']=[21.1,3.25,3.65]


def gardens(kit, box, place):
    bands=[]
    kit.begin('garden_supports_TerraceZone',ao=False)
    # Six clusters per two-metre band, grouped three of one species then three
    # of the next. Raised earth puts flowers above the foreground stone rail.
    species=['alc_flowers_poppy','alc_flowers_lavender','alc_flowers_daisy']
    for row,(y,z) in enumerate([(3.25,4.55),(5.5,.05),(7.75,-4.45)]):
        for band,x in enumerate([-17.8,-6.0,4.8]):
            box('raised_flower_band_%d_%d'%(row,band),(x,y+.15,z),(2.35,.30,.90),'soil',.03)
            for i in range(6):
                p=place(species[(row+band+i//3)%3],(x-0.8+i*.32,y+.3,z+(.13 if i%2 else -.13)),collision=False)
                p['support_y_offset_m']=.3
            bands.append({'terrace':row+1,'center':[x,y+.3,z],'length_m':2,'clusters':6})
        # End-compatible one-metre hedges form a single uninterrupted green line.
        for i in range(4):place('alc_hedge',(-12+i,y,z-.6),collision=False)
    place('garden_supports_TerraceZone',zone='TerraceZone')
    # Eastern stair markers stay below waist height; western corners use pots.
    for y,z in [(3.25,6.8),(5.5,1.15),(7.75,-2.2),(10,-6.35)]:
        zone='SummitZone' if y==10 else 'TerraceZone'
        for x in [10.25,11.05]:place('alc_flowers_daisy',(x,y,z),zone,collision=False)
    for zone,y,points in [('DockZone',1,[(-23.6,12.5),(-23.6,13.5)]),
            ('TerraceZone',3.25,[(-24.2,5.3),(-23.2,5.3)]),
            ('TerraceZone',5.5,[(-25.2,.95),(-24.2,.95)]),
            ('TerraceZone',7.75,[(-24.2,-3.55),(-23.2,-3.55)])]:
        for x,z in points:place('alc_planter',(x,y,z),zone,collision=True)
    return {'flower_bands':bands,'corner_markers':'east paired low flowers; west paired terracotta planters','hedge_runs':3}


def endpoints(p):
    v=p.get('basis_columns',[[math.cos(p['yaw'])*p['scale'][0],0,-math.sin(p['yaw'])*p['scale'][0]]])[0]
    return [[p['position'][k]+s*v[k] for k in range(3)] for s in [-1,1]]


def set_segment(p,a,b):
    p['position']=[(a[k]+b[k])/2 for k in range(3)]
    length=math.hypot(b[0]-a[0],b[2]-a[2]);p['scale']=[length/2,1,1]
    p['yaw']=math.atan2(-(b[2]-a[2]),b[0]-a[0])
    p['basis_columns']=[[(b[k]-a[k])/2 for k in range(3)],[0,1,0],[math.sin(p['yaw']),0,math.cos(p['yaw'])]]
    p['slope_rise_m']=b[1]-a[1]


def connect_rails(placements,place):
    """Meet slope/landing heights and replace tiny double-post stubs with corners.

    Vertical axes stay unit length. Only run length and rail slope are adjusted;
    the approved one-metre posts never get stretched vertically.
    """
    rails=[p for p in placements if p['asset']=='alc_rail_straight']
    curbs=[p for p in placements if p['asset']=='alc_curb']
    joins=defaultdict(list)
    for i,p in enumerate(rails):
        for side,v in enumerate(endpoints(p)):joins[(round(v[0],4),round(v[2],4))].append((i,side,v))
    corrected=0;corners=0;removed=[]
    for entries in joins.values():
        if len(entries)!=2:continue
        a,b=entries
        if abs(a[2][1]-b[2][1])<.01:continue
        flat,sloped=(a,b) if abs(rails[a[0]].get('slope_rise_m',0))<.01 else (b,a)
        if abs(rails[flat[0]].get('slope_rise_m',0))>.01:continue
        target=flat[2][1]
        for source in [rails,curbs]:
            p=source[sloped[0]];ends=endpoints(p);ends[sloped[1]][1]=target;set_segment(p,*ends)
        corrected+=1
        short=rails[flat[0]];run=rails[sloped[0]]
        se=endpoints(short);re=endpoints(run)
        if math.dist(se[0],se[1])>.501:continue
        corner=se[flat[1]];tip=se[1-flat[1]]
        end=re[1-sloped[1]];distance=math.hypot(end[0]-corner[0],end[2]-corner[2])
        trim=min(.5,distance)
        run_tip=[corner[k]+(end[k]-corner[k])*trim/distance for k in range(3)]
        vx=[(tip[k]-corner[k])*2 for k in range(3)];vz=[(run_tip[k]-corner[k])*2 for k in range(3)]
        if vx[0]*vz[2]-vx[2]*vz[0]<0:vx,vz=vz,vx
        yaw=math.atan2(-vx[2],vx[0])
        p=place('alc_rail_corner',corner,short['zone'],yaw=yaw,collision=False)
        p['basis_columns']=[vx,[0,1,0],vz]
        p['scale']=[math.hypot(vx[0],vx[2]),1,math.hypot(vz[0],vz[2])]
        p['slope_rise_m']=0
        removed.append(short)
        if distance<=.501:removed.append(run)
        else:
            re[sloped[1]]=run_tip;set_segment(run,*re)
        corners+=1
    placements[:]=[p for p in placements if not any(p is q for q in removed)]
    return {'height_junctions_fixed':corrected,'single_post_connectors':corners}


def tree_replacements(here,placements):
    table=json.loads((here.parent/'alcatraz_trees_cd_424/suggested_replacements.json').read_text())
    rows={p['source_name']:p for p in table['replacements']};counts=defaultdict(int);applied=[]
    for p in placements:
        name='%s_%03d'%(p['asset'],counts[p['asset']]);counts[p['asset']]+=1
        if not p['asset'].startswith('alc_tree_'):continue
        p['source_name']=name
        if name not in rows:continue
        row=rows[name]
        assert p['position']==row['position'],(name,p['position'],row['position'])
        assert abs(p['yaw']-row['yaw'])<1e-6,name
        p['asset']=row['asset'];applied.append(name)
    assert len(applied)==12
    return {'source':'#826 / 4d8cdab5','replaced':applied,'root_positions_preserved':True,'counts':table['after_counts']}
