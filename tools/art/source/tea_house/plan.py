"""Tea House metre layout preflight with full-size seating and capsule routes."""
from pathlib import Path
from collections import deque
import json
import math
import numpy as np
from shapely.geometry import Point, box, LineString
from shapely.ops import unary_union

ROOT=Path(__file__).resolve().parents[4]
SRC=Path(__file__).resolve().parent
OUT=ROOT/'output/tea-216'
FLOOR=.08


def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')


def main():
    items=[];anchors=[]
    def obstacle(name,at,size=None,radius=None,kind='box'):
        nav_radius=radius+.02 if kind=='table' else radius
        footprint=Point(at[0],at[2]).buffer(nav_radius,quad_segs=32) if radius else box(at[0]-size[0]/2,at[2]-size[2]/2,at[0]+size[0]/2,at[2]+size[2]/2)
        row={'name':name,'position':at,'size':size,'radius':radius,'kind':kind,'shape':footprint}
        items.append(row);return row
    def anchor(name,position,yaw=0,module=None,**extra):
        row={'name':name,'position':position,'yaw_degrees':yaw,**extra}
        if module:row['module']=module
        anchors.append(row);return row
    obstacle('counter',[-.50,FLOOR,-1.95],[2.2,1.15,.65])
    obstacle('window_bench',[-2.93,FLOOR,-.40],[.50,.715,2.10])
    obstacle('coffee_console',[1.45,FLOOR,-2.63],[1.0,.72,.50])
    obstacle('corner_tree',[-2.50,FLOOR,2.22],radius=.32,kind='plant')
    tables=[(-.95,-.10,[0,120,240]),(.35,1.50,[60,180,300]),(1.85,.05,[0,120,240])]
    for table_number,(x,z,angles) in enumerate(tables,1):
        name='tea_table_'+str(table_number)
        obstacle(name,[x,FLOOR,z],radius=.45,kind='table')
        anchor('use_'+name,[x,FLOOR+1.0,z],module=name)
        for i,degrees in enumerate(angles,1):
            angle=math.radians(degrees);dx,dz=math.sin(angle),math.cos(angle)
            px,pz=x+.84*dx,z+.84*dz;stool='stool_%d_%d'%(table_number,i)
            obstacle(stool,[px,FLOOR,pz],radius=.28,kind='stool')
            approach=[px+.57*dx,FLOOR,pz+.57*dz]
            if table_number==3 and i==2:approach=[px+.20,FLOOR,pz-.54]
            anchor('seat_table%d_%d'%(table_number,i),[px,FLOOR+.715,pz],degrees,stool,approach=approach)
    anchor('use_bench',[-2.68,FLOOR+.715,-.4],-90,'window_bench')
    for i,z in enumerate([-1.10,-.40,.30],1):
        anchor('seat_bench_'+str(i),[-2.88,FLOOR+.715,z],-90,'window_bench',approach=[-2.30,FLOOR,z])
    anchor('use_counter',[-.5,FLOOR+1.15,-1.95],module='counter')
    anchor('stand_counter',[-.50,FLOOR,-1.23],0,'counter')
    anchor('stand_keeper',[-.50,FLOOR,-1.23],0,'counter')
    anchor('npc_keeper',[-.5,FLOOR,-2.64],180,'counter')
    anchor('badge_keeper',[-.5,FLOOR+2.05,-2.64],180,'counter')
    anchor('npc_hana',[2.50,FLOOR,-1.98],180,'coffee_console')
    anchor('stand_hana',[2.50,FLOOR,-1.16],0,'coffee_console')
    anchor('npc_lena',[-2.65,FLOOR,1.16],-90,'window_bench')
    anchor('stand_lena',[-1.83,FLOOR,1.20],90,'window_bench')
    anchor('spawn',[.30,FLOOR,2.55],0)
    anchor('exit',[.30,FLOOR,3.80],180)
    anchor('badge_exit',[.30,1.05,3.80],180)
    anchor('sign_name',[-2.3925,3.20,-2.812],180,'name_sign',size=[1.04,.26])
    anchor('cam_default',[.10,1.1,.4],45,width_m=6.72,pitch_degrees=43)
    room=box(-3.2,-3.0,3.2,3.0)
    domain=unary_union([room,box(-.35,2.9,.95,4.20)])
    collisions=unary_union([p['shape'] for p in items])
    failures=[]
    for i,item in enumerate(items):
        if not room.covers(item['shape']):failures.append([item['name'],'outside interior'])
        for other in items[:i]:
            if item['shape'].intersection(other['shape']).area>1e-6:failures.append([item['name'],other['name'],'overlap'])
    def reachable(radius):
        allowed=domain.buffer(-radius);blocked=collisions.buffer(radius+.002)
        points={}
        for iz in range(138):
            for ix in range(122):
                x,z=-3.025+ix*.05,-2.825+iz*.05
                point=Point(x,z)
                if allowed.covers(point) and not blocked.intersects(point):points[(ix,iz)]=(x,z)
        start=min(points,key=lambda p:math.dist(points[p],(.3,2.55)))
        previous={start:start};queue=deque([start])
        while queue:
            cell=queue.popleft()
            for delta in [(1,0),(-1,0),(0,1),(0,-1)]:
                nxt=(cell[0]+delta[0],cell[1]+delta[1])
                if nxt in points and nxt not in previous:previous[nxt]=cell;queue.append(nxt)
        return points,previous,start
    points,previous,start=reachable(.25)
    targets=[a for a in anchors if a['name'].startswith(('seat_','stand_','npc_')) or a['name']=='exit']
    routes=[]
    for target in targets:
        position=target.get('approach',target['position']);xz=(position[0],position[2])
        nearest=min(points,key=lambda p:math.dist(points[p],xz))
        reached=nearest in previous and math.dist(points[nearest],xz)<.10
        if not reached:failures.append([target['name'],'unreachable',points[nearest],xz])
        path=[];cell=nearest
        if reached:
            while cell!=start:path.append(points[cell]);cell=previous[cell]
            path.append(points[start]);path.reverse()
        routes.append({'name':target['name'],'target_xz':xz,'passed':reached,'points_xz':path})
    npc_positions=[(a['position'][0],a['position'][2]) for a in anchors if a['name'].startswith('npc_')]
    standing=[];available=[points[cell] for cell in previous if room.buffer(-.25).covers(Point(points[cell]))
                          and all(math.dist(points[cell],npc)>=.70 for npc in npc_positions)]
    while available and len(standing)<16:
        candidate=max(available,key=lambda q:min([math.dist(q,other) for other in standing] or [100]))
        if standing and min(math.dist(candidate,other) for other in standing)<.7:break
        standing.append(candidate);available.remove(candidate)
    if len(standing)!=16:failures.append(['standing_count',len(standing)])
    wide,wide_reached,_=reachable(.35)
    main_routes=[]
    wide_start=next(key for key,value in wide_reached.items() if key==value)
    for name in ['stand_counter','stand_hana','exit']:
        target=next(a for a in anchors if a['name']==name)['position'];xz=(target[0],target[2])
        nearest=min(wide,key=lambda p:math.dist(wide[p],xz))
        if nearest not in wide_reached or math.dist(wide[nearest],xz)>.12:
            failures.append([name,'main route below .70m',wide[nearest],xz,nearest in wide_reached])
        else:
            route=[];cell=nearest
            while cell!=wide_start:route.append(wide[cell]);cell=wide_reached[cell]
            route.append(wide[wide_start]);route.reverse()
            main_routes.append({'name':name,'points_xz':route})
    result={'passed':not failures,'failures':failures,'seat_count':12,'standing_positions_xz':standing,'routes':routes,
            'capsule':{'radius_m':.25,'height_m':1.745,'grid_step_m':.05},'main_route_radius_m':.35,'main_routes':main_routes,
            'note':'Analytic preflight from authored metre envelopes; verify raw exported bounds and Godot physics next.'}
    write(SRC/'blockout_plan.json',{'floor_y':FLOOR,'room_size_m':[6.8,6.4],
          'items':[{k:v for k,v in p.items() if k!='shape'} for p in items],'anchors':anchors,'preflight':result})
    write(OUT/'blockout-preflight.json',result)
    from PIL import Image,ImageDraw
    image=Image.new('RGB',(900,1000),'white');draw=ImageDraw.Draw(image)
    def pixel(x,z):return ((x+3.6)*115,(z+3.4)*115)
    for key,point in wide.items():
        x,y=pixel(*point);draw.rectangle((x-2,y-2,x+2,y+2),fill='#a6d8be' if key in wide_reached else '#dce4e9')
    for item in items:
        draw.polygon([pixel(x,z) for x,z in item['shape'].exterior.coords],fill='#c3a47d',outline='#66543d')
        draw.text(pixel(item['position'][0]-.25,item['position'][2]),item['name'],fill='black')
    for anchor in anchors:
        if anchor['name'].startswith(('stand_','npc_')) or anchor['name'] in ['spawn','exit']:
            x,_,z=anchor['position'];px,py=pixel(x,z)
            draw.ellipse((px-5,py-5,px+5,py+5),fill='#d53a4a');draw.text((px+6,py),anchor['name'],fill='black')
    image.save(OUT/'blockout-preflight.png')
    print(json.dumps({'passed':result['passed'],'failures':failures,'standing':len(standing)},indent=2))


if __name__=='__main__':main()
