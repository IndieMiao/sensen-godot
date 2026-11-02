"""Authored blockouts checked against measured footprints with Shapely."""
import copy
import json
import math
from collections import deque
import numpy as np
from shapely.geometry import box, Point, LineString
from shapely.affinity import rotate, translate
from shapely.ops import unary_union, nearest_points
from dependencies import SRC, write_json

MEASURE=json.loads((SRC/'measured_dependencies.json').read_text())
MEASURE['small_round_table']={'bounds':[[-.30,0,-.30],[.30,.75,.30]],'dimensions_m':[.60,.75,.60],'seat_anchors':{}}
for name,source,width in [('sofa_narrow','sofa_three_seat',2.30),('armchair_narrow','armchair',1.30)]:
    spec=copy.deepcopy(MEASURE[source]);factor=width/spec['dimensions_m'][0]
    spec['source_asset']=source;spec['preview_scale']=[factor,1,1]
    spec['dimensions_m'][0]=width
    for bound in spec['bounds']:bound[0]*=factor
    if name=='sofa_narrow':
        for i,anchor in enumerate(spec['seat_anchors'].values()):anchor[0]=(i-1)*.70
    MEASURE[name]=spec
FLOOR=.08
ROOM=box(-3.18,-2.98,3.34,3.14)
CENTER=(.04,.18)
BASE=Point(*CENTER).buffer(.93,quad_segs=64)
ENTRY=box(-.37,1.75,.37,3.15)


def transform(x,z,yaw,at):
    a=math.radians(yaw)
    return [at[0]+math.cos(a)*x+math.sin(a)*z,at[1]-math.sin(a)*x+math.cos(a)*z]


def item(name,asset,x,z,yaw=0):
    measurement=MEASURE[asset];lo,hi=measurement['bounds']
    if asset in ['round_side_table','small_round_table']:shape=Point(0,0).buffer(hi[0],quad_segs=32)
    elif asset=='peace_lily':shape=Point(0,0).buffer(.245,quad_segs=32)
    else:shape=box(lo[0],lo[2],hi[0],hi[2])
    shape=translate(rotate(shape,-yaw,origin=(0,0)),x,z)
    seats=[]
    for local in measurement.get('seat_anchors',{}).values():
        at=transform(local[0],local[2],yaw,(x,z));approach=transform(local[0],hi[2]+.36,yaw,(x,z))
        seats.append({'position':[at[0],FLOOR+local[1],at[1]],'yaw_degrees':yaw,
                      'approach':[approach[0],FLOOR,approach[1]],'module':name})
    return {'name':name,'asset':asset,'position':[x,FLOOR,z],'yaw_degrees':yaw,
            'source_asset':measurement.get('source_asset',asset),'scale':measurement.get('preview_scale',[1,1,1]),
            'bounds_local':measurement['bounds'],'seats':seats,'shape':shape,
            'pot_collision':{'radius':.245,'height':.39} if asset=='peace_lily' else None,
            'approach_shapes':[Point(s['approach'][0],s['approach'][2]).buffer(.35,quad_segs=24) for s in seats]}


def proxy(name,size,x,z,yaw=0,bottom=0,kind='box',collision=True):
    shape=Point(0,0).buffer(size[0]/2,quad_segs=64) if kind=='cylinder' else box(-size[0]/2,-size[2]/2,size[0]/2,size[2]/2)
    shape=translate(rotate(shape,-yaw,origin=(0,0)),x,z)
    return {'name':name,'asset':'proxy','size':size,'position':[x,FLOOR+bottom+size[1]/2,z],
            'yaw_degrees':yaw,'kind':kind,'collidable':collision,'shape':shape,'seats':[],'approach_shapes':[]}


FIXED=[proxy('sculpture_base',[1.86,.40,1.86],*CENTER,kind='cylinder'),
       proxy('sculpture_body',[1.09,1.50,1.09],*CENTER,bottom=.40,kind='cylinder',collision=False),
       proxy('display_niche_1',[1.10,2.40,.35],-1.65,-2.805),proxy('display_niche_2',[1.10,2.40,.35],1.65,-2.805),
       proxy('brochure_rack',[.71,1.10,.48],-.10,-2.69,8),proxy('water_dispenser',[.44,1.30,.54],3.02,-2.64),
       proxy('window_box_1',[.22,.20,1.0],-3.08,-1.78,bottom=.92),proxy('window_box_2',[.22,.20,1.0],-3.08,1.78,bottom=.92)]


def validate(items):
    fixed=[p for p in FIXED if p['collidable']]
    for i,p in enumerate(items):
        assert ROOM.covers(p['shape']),(p['name'],'outside room')
        assert not p['shape'].intersects(ENTRY),(p['name'],'entry corridor')
        for other in items[:i]+fixed:
            assert p['shape'].intersection(other['shape']).area<1e-7,(p['name'],other['name'],'overlap')
        for approach in p['approach_shapes']:
            assert ROOM.covers(approach),(p['name'],'approach outside')
            for other in items+fixed:
                if other is p:continue
                assert not approach.intersects(other['shape']),(p['name'],other['name'],'approach blocked')
    nearest=min(items,key=lambda p:p['shape'].distance(BASE));gap=nearest['shape'].distance(BASE)
    assert gap>=.70,('sculpture circle',gap,nearest['name'])
    a,b=nearest_points(BASE,nearest['shape'])
    union=unary_union([p['shape'] for p in items+fixed]);entrance=[]
    for z in np.arange(1.82,2.89,.02):
        free=LineString([(-3.18,float(z)),(3.34,float(z))]).difference(union)
        for segment in getattr(free,'geoms',[free]):
            if segment.distance(Point(0,z))<1e-8:entrance.append(segment.length)
    assert entrance and min(entrance)>=.70
    return {'ring_min_m':gap,'ring_nearest_module':nearest['name'],
            'ring_measurement_xz':[list(a.coords[0]),list(b.coords[0])],
            'entry_min_m':min(entrance),'main_min_m':min(gap,min(entrance))}


def routes(items):
    obstacles=[p['shape'] for p in FIXED if p.get('collidable',True)]+[p['shape'] for p in items]
    blocked=unary_union(obstacles).buffer(.25,quad_segs=24);domain=ROOM.buffer(-.25);points={}
    for iz in range(59):
        for ix in range(62):
            x,z=-2.95+ix*.1,-2.70+iz*.1
            if domain.covers(Point(x,z)) and not blocked.intersects(Point(x,z)):points[(ix,iz)]=(x,z)
    def nearest(p):return min(points,key=lambda k:math.dist(points[k],p))
    start=nearest((0,2.5));previous={start:start};queue=deque([start])
    while queue:
        cell=queue.popleft()
        for dx,dz in [(1,0),(-1,0),(0,1),(0,-1)]:
            nxt=(cell[0]+dx,cell[1]+dz)
            if nxt in points and nxt not in previous:previous[nxt]=cell;queue.append(nxt)
    paths=[]
    for seat in [seat for p in items for seat in p['seats']]:
        target=(seat['approach'][0],seat['approach'][2]);end=nearest(target)
        assert end in previous and math.dist(points[end],target)<.10,seat
        route=[target];cell=end
        while cell!=start:route.append(points[cell]);cell=previous[cell]
        route.append(points[start]);route.reverse()
        paths.append({'module':seat['module'],'target':list(target),'points_xz':route})
    standing=[points[start]]
    available=[points[cell] for cell in previous]
    while len(standing)<16:
        point=max(available,key=lambda p:min(math.dist(p,other) for other in standing))
        assert min(math.dist(point,other) for other in standing)>=.70
        standing.append(point);available.remove(point)
    assert len(standing)==16
    return {'routes':paths,'standing_positions_xz':standing,'reachable_cells':len(previous),'grid_step_m':.1}


def clean(row):return {k:v for k,v in row.items() if k not in ['shape','approach_shapes']}


def main():
    specifications={
      'A1':[
        ('sofa_1','sofa_three_seat',-2.37,-.10,90),('sofa_2','sofa_three_seat',2.83,.70,-90),
        ('armchair_1','armchair',-1.50,-2.02,0),('armchair_2','armchair',-2.37,2.10,90),
        ('armchair_3','armchair',.10,-1.92,0),('armchair_4','armchair',1.80,2.63,180),('armchair_5','armchair',2.83,-1.50,-90),
        ('table_1','small_round_table',-1.35,2.80,0),('plant_1','peace_lily',-.75,2.65,0),('plant_2','peace_lily',.75,2.65,0)],
      'A2':[
        ('sofa_1','sofa_narrow',-2.37,.65,90),('sofa_2','sofa_narrow',2.83,.80,-90),
        ('armchair_1','armchair_narrow',-2.37,-1.95,90),('armchair_2','armchair_narrow',-2.37,2.48,90),
        ('armchair_3','armchair_narrow',2.83,-1.67,-90),('armchair_4','armchair_narrow',1.60,2.63,180),('armchair_5','armchair_narrow',0,-1.92,0),
        ('table_1','small_round_table',-2.50,-.90,0),('table_2','small_round_table',2.95,-.685,0),('table_3','small_round_table',2.85,2.60,0),
        ('plant_1','peace_lily',1.10,-2.25,0),('plant_2','peace_lily',-.85,2.75,0)],
      'B':[
        ('sofa_1','sofa_three_seat',-2.37,1.25,90),('sofa_2','sofa_three_seat',2.83,1.45,-90),
        ('armchair_1','armchair',-2.37,-1.85,90),('armchair_2','armchair',2.83,-1.55,-90),
        ('table_1','small_round_table',-2.48,-.75,0),('table_2','small_round_table',2.95,-.40,0),('table_3','small_round_table',1.70,2.82,0),
        ('plant_1','peace_lily',.75,-2.45,0),('plant_2','peace_lily',-.95,-2.0,0),
        ('plant_3','peace_lily',-1.10,2.70,0),('plant_4','peace_lily',.85,2.65,0)]}
    tradeoffs={
      'A1':['11 original-size seats','1 small table instead of 3 original tables','2 floor plants instead of 4','Two chairs placed in front of the display wall'],
      'A2':['11 seats, sofa 2.30m and armchair 1.30m X-only blockout scale','3 small tables, 2 plants','Detailed assets require source remodelling after layout approval'],
      'B':['8 original-size seats, 3 small tables, 4 plants','Left and right waiting groups; display wall kept clear','Recommended for circulation and reference composition']}
    layouts=[]
    for name,rows in specifications.items():
        placed=[item(*row) for row in rows];clearance=validate(placed);nav=routes(placed)
        seats=[seat for p in placed for seat in p['seats']];sofa_n=arm_n=0
        for seat in seats:
            if seat['module'].startswith('sofa'):sofa_n+=1;seat['name']='seat_sofa_'+str(sofa_n)
            else:arm_n+=1;seat['name']='seat_armchair_'+str(arm_n)
        layouts.append({'id':name,'floor_y':FLOOR,'footprint_m':[6.8,6.4],
                        'items':[clean(p) for p in placed],'fixed':[clean(p) for p in FIXED],
                        'seat_count':len(seats),'anchors':seats,'navigation_plan':nav,'clearance':clearance,
                        'sculpture_clearance_m':clearance['ring_min_m'],'tradeoffs':tradeoffs[name],
                        'spawn':[0,FLOOR,2.5],'exit':[0,FLOOR,2.88]})
        print(name,len(seats),'seats',clearance,flush=True)
    write_json(SRC/'blockout_layouts.json',{'task':'SGODOT-321','phase':'three blockouts; approval required before detailed art',
        'shell_unchanged':True,'minimum_main_clearance_m':.70,'layouts':layouts})
    used={p['asset'] for layout in layouts for p in layout['items']}
    for asset in used:
        spec=MEASURE[asset]
        record={'task':'SGODOT-321','author':'Huangzhong','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
                'asset':asset,'phase':'neutral blockout','measured_or_proposed_bounds':spec['bounds'],
                'source_asset':spec.get('source_asset',asset),'source_sha256':spec.get('sha256'),
                'changes':'Approved X-only node scale, Y/Z unchanged; detailed source remodelling deferred' if 'preview_scale' in spec else 'Existing geometry unchanged, neutral review material override',
                'scale':spec.get('preview_scale',[1,1,1])}
        if asset=='small_round_table':record['changes']='New 0.60m diameter / 0.75m height white proxy; no detailed asset claimed'
        write_json(SRC/'provenance'/asset/'reuse_provenance.json',record)
    for proxy in FIXED:
        write_json(SRC/'provenance'/proxy['name']/'reuse_provenance.json',{
            'task':'SGODOT-321','author':'Huangzhong','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
            'asset':proxy['name'],'phase':'new white volume only','size_m':proxy['size'],
            'source':'Shangguan dispatch huangzhong-320v11-321-n2.txt','changes':'Placeholder envelope; detail and final palette await layout selection'})


if __name__=='__main__':main()
