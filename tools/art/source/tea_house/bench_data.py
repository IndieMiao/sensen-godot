"""Tea House adapter for the unchanged seven-group shared scene benchmark."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[4]
KIT=ROOT/'assets/rooms/tea_house'
SRC=Path(__file__).resolve().parent


def main():
    layout=json.loads((KIT/'layout.json').read_text())
    plan=json.loads((SRC/'blockout_plan.json').read_text())
    layout['preflight']=plan['preflight']
    layout['review_lighting']['points']=[]
    layout['review_lighting'].update({'shadow_bias':.05,'shadow_normal_bias':.30})
    layout['bench']={'floor_y':.08,
        'route':[{'name':name,'position':position,**({'capture':capture} if capture else {})} for name,position,capture in [
            ('spawn',[.30,.08,2.55],None),('entry_inside',[.30,.08,2.80],'door'),
            ('left_entry',[-1.30,.08,2.55],None),('lena_corner',[-1.83,.08,1.20],None),
            ('window_bench',[-2.30,.08,-.10],None),('counter_left',[-2.15,.08,-1.20],None),
            ('counter_front',[-.50,.08,-1.23],'main'),('coffee_corner',[1.20,.08,-1.25],None),
            ('hana_front',[2.50,.08,-1.16],None),('rear_door',[2.70,.08,-2.10],None)]],
        'blocked':[{'name':name,'from':start,'to':end,'target':target} for name,start,end,target in [
            ('counter',[-.5,.08,-1.23],[-.5,.08,-2.1],'/counter/'),
            ('tea_table',[.35,.08,2.45],[.35,.08,1.5],'/tea_table_2/'),
            ('round_stool',[1.08,.08,2.65],[1.08,.08,1.92],'/stool_2_1/'),
            ('window_bench',[-2.30,.08,-.4],[-2.93,.08,-.4],'/window_bench/'),
            ('left_wall',[-2.60,.08,-2.35],[-3.6,.08,-2.35],'/left_wall/'),
            ('back_wall',[-2.50,.08,-2.60],[-2.5,.08,-3.6],'/back_wall/'),
            ('right_boundary',[2.80,.08,2.55],[3.60,.08,2.55],'RightBoundary'),
            ('front_left',[-1.50,.08,2.65],[-1.50,.08,3.80],'FrontLeftBoundary'),
            ('front_right',[2.50,.08,2.65],[2.50,.08,3.80],'FrontRightBoundary'),
            ('landing_left',[.30,.08,3.60],[-.90,.08,3.60],'LandingLeft'),
            ('landing_right',[.30,.08,3.60],[1.50,.08,3.60],'LandingRight'),
            ('landing_end',[.30,.08,3.65],[.30,.08,4.80],'LandingEnd')]],
        'gaps':[{'name':'entry','from':[.30,.08,2.70],'to':[.30,.08,3.60],
                 'measure':[[-.35,.73,3.06],[.95,.73,3.06]],'minimum':.70,'width':1.30},
                {'name':'counter_aisle','from':[-1.10,.08,-1.20],'to':[.35,.08,-1.20],
                 'measure':[[-.22253866,.73,-1.625],[-.22253866,.73,-.80]],'minimum':.70,'width':.825}],
        'entrance':{'inside':[.30,.08,2.80],'outside':[.30,.08,3.65]},
        'slide':{'from':[2.95,.08,-2.30],'direction':[1,0,1],'tangent':[0,0,1],'seconds':.60},
        'input_start':[-1.40,.08,2.50],
        'scale':{'door':{'height':2.33,'source':'Decorative closed door panel local top 2.33m above floor; front entry is open'},
                 'counter':{'height':1.15,'source':'Named counter top upper vertices, local y=1.15m'},
                 'chair':{'height':.715,'source':'Upholstered stool pad and window bench upper vertices, local y=.715m'},
                 'table':{'height':1.0,'source':'Round table upper wooden surface, local y=1.0m; director-approved raised tea tables'}}}
    (KIT/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2)+'\n')


if __name__=='__main__':main()
