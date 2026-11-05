"""Church data adapter for the unchanged shared scene_bench harness."""
from pathlib import Path
import json,math
ROOT=Path(__file__).resolve().parents[4];KIT=ROOT/'assets/rooms/poi_church';R=math.sqrt(.5);F=.08
def uv(u,v,y=F):return [(u+v)*R,y,(-u+v)*R]
def main():
 p=KIT/'layout.json';l=json.loads(p.read_text())
 l['bench']={'floor_y':F,'route':[{'name':n,'position':pos,**({'capture':cap} if cap else {})} for n,pos,cap in [
  ('spawn',uv(-1.8,4.15),None),('entry_inside',[2.0,F,4.75],'door'),('labyrinth',uv(0,4.15),None),
  ('aisle_front',uv(0,2.5),None),('aisle_mid',uv(0,.6),'main'),('aisle_rear',uv(0,-2.6),None),
  ('left_seat_approach',uv(-1.25,-2.52),None),('return_aisle',uv(0,-2.52),None)]],
  'blocked':[{'name':n,'from':a,'to':b,'target':t} for n,a,b,t in [
   ('pew_left',uv(-1.3,3.45),uv(-1.3,2.65),'/pew_left_4/'),
   ('altar_table',uv(0,-2.6),uv(0,-4.5),'/altar_table/'),
   ('west_wall',[-4.70,F,0],[-5.8,F,0],'/west_wall/'),
   ('east_boundary',[4.6,F,1],[5.8,F,1],'EastBoundary'),
   ('front_edge',[-1,F,4.7],[-1,F,5.9],'FrontLeftBoundary'),
   ('landing_end',[2.0,F,5.9],[2.0,F,7],'LandingEnd')]],
  'gaps':[{'name':'entry','from':[2.0,F,4.75],'to':[2.0,F,5.95],
    'measure':[[1.3,.73,5.6],[2.7,.73,5.6]],'minimum':1.2,'width':1.4},
   {'name':'central_aisle','from':uv(0,2.5),'to':uv(0,-2.6),'measure':[uv(-.8,1.15,.73),uv(.8,1.15,.73)],'minimum':.8,'width':1.6},
   {'name':'between_rows','from':uv(0,.4),'to':uv(-2.1,.4),'measure':[uv(-2.1,-.025,.73),uv(-2.1,.825,.73)],'minimum':.8,'width':.85}],
  'entrance':{'inside':[2.0,F,4.75],'outside':[2.0,F,5.95]},
  'slide':{'from':[4.85,F,1.0],'direction':[1,0,1],'tangent':[0,0,1],'seconds':.60},
  'input_start':uv(0,3.85),
  'scale':{'door':{'applicable':False,'reason':'Open cutaway entrance, no functional door leaf; width measured by collision rays.'},
   'counter':{'applicable':False,'reason':'No service counter or NPC transaction position in this decorative interior.'},
   'chair':{'height':.715,'source':'Pew seat plank top at local y .715 m, measured in exported vertices.'},
   'table':{'height':1.12,'source':'Altar table top, relative to sanctuary upper platform; cloth adds .01 m.'}}}
 p.write_text(json.dumps(l,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
