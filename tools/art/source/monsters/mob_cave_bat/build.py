"""SGODOT-355 cave bat pilot: rounded rigid parts and final animation interface."""
from pathlib import Path
import math
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent.parent))
import rigid_model as m

ID='mob_cave_bat'
ANIMS={'idle':{'length':1.0,'loop':True},'move':{'length':.6,'loop':True},
    'windup':{'length':.55,'loop':False},'attack':{'length':.45,'loop':False,'hit_at':.20},
    'recover':{'length':.50,'loop':False},'hit':{'length':.25,'loop':False},
    'die':{'length':.70,'loop':False},'fly_high':{'length':.4,'loop':True}}


def pose(name,u,t,bones):
    body=bones['body'];flap=0;fold=0
    cycle=u*math.tau if name in ['idle','move','fly_high'] else t*math.tau
    if name in ['idle','move','fly_high']:
        phase=u*math.tau*(2 if name=='idle' else 1)
        flap=math.sin(phase)*(.55 if name=='idle' else .80)
        body.location.z=.015*math.sin(phase)
        body.rotation_euler.x=math.radians(-12 if name=='fly_high' else 10 if name=='move' else 0)
    elif name=='windup':
        fold=u*.95;flap=-u*.25;body.rotation_euler.x=math.radians(22*u)
        body.scale=(1-.08*u,1-.08*u,1+.04*u)
    elif name=='attack':
        strike=math.sin(math.pi*min(1,u/.45)) if u<.45 else 0
        fold=.95*(1-min(1,u/.4));flap=-.70*math.sin(math.pi*u)
        body.rotation_euler.x=math.radians(22+36*math.sin(math.pi*u))
        body.location.z=-.09*math.sin(math.pi*u);body.scale=(1-.05*strike,1+.1*strike,1-.06*strike)
    elif name=='recover':
        flap=-.30*math.sin(math.pi*u);body.rotation_euler.x=math.radians(22*(1-u))
    elif name=='hit':
        k=math.sin(math.pi*u);flap=-.35*k;fold=.3*k
        body.rotation_euler.x=math.radians(-18*k);body.scale=(1+.10*k,1-.12*k,1-.08*k)
    elif name=='die':
        k=min(1,u/.85);fold=k;flap=-.5*k;body.rotation_euler.x=math.radians(-85*k)
        body.location.z=-.78*k;body.scale=(max(.12,1-k*.88),)*3
    for side,sign in [('l',-1),('r',1)]:
        bones['wing_'+side+'1'].rotation_euler.y=sign*flap
        bones['wing_'+side+'1'].rotation_euler.z=sign*fold*.55
        bones['wing_'+side+'2'].rotation_euler.z=sign*(fold+.10*math.sin(cycle*2))
        bones['ear_'+side].rotation_euler.y=sign*.06*math.sin(cycle)
        bones['foot_'+side].rotation_euler.x=.12*math.sin(cycle*2+sign*.3)


def main():
    mat=m.start(ID)
    m.ellipsoid('Round lavender body',(0,1,0),(.40,.40,.33),'A794BF','body',1,mat,16,8)
    for side,sign in [('l',-1),('r',1)]:
        m.ellipsoid('Rounded ear '+side,(sign*.115,1.205,-.01),(.105,.22,.07),'A794BF','ear_'+side,1,mat,8,6,sign*18)
        m.ellipsoid('Rose inner ear '+side,(sign*.116,1.213,.027),(.059,.145,.018),'D7ACCA','ear_'+side,0,mat,8,6,sign*18)
        m.ellipsoid('Tiny rounded foot '+side,(sign*.075,.79,0),(.055,.09,.06),'82708F','foot_'+side,1,mat,8,4)
        m.ellipsoid('Black eye '+side,(sign*.079,1.025,.153),(.038,.054,.026),'30303C','body',0,mat,8,6)
        m.ellipsoid('White eye glint '+side,(sign*.079-.006,1.038,.166),(.013,.016,.009),'FFF8ED','body',0,mat,6,4)
        m.ellipsoid('Pink cheek '+side,(sign*.126,.978,.136),(.055,.028,.012),'E8B0C6','body',0,mat,8,4)
        inner=[(.13,1.08),(.18,1.16),(.26,1.25),(.31,1.27),(.325,1.18),(.32,1.02),(.28,1.04),(.24,1.035),(.18,.98),(.145,.97)]
        outer=[(.30,1.27),(.36,1.245),(.43,1.205),(.48,1.15),(.50,1.115),(.48,1.10),(.455,1.10),(.425,1.085),(.405,1.035),(.38,1.06),(.35,1.06),(.31,1.025)]
        m.pillow('Inner wing membrane '+side,[(sign*x,y) for x,y in inner],-.045,'9984AF','wing_'+side+'1',mat)
        m.pillow('Outer scalloped wing '+side,[(sign*x,y) for x,y in outer],-.045,'9984AF','wing_'+side+'2',mat)
        m.ellipsoid('Round wing joint '+side,(sign*.305,1.263,-.045),(.04,.045,.04),'AA98BD','wing_'+side+'2',1,mat,8,4)
    m.ellipsoid('Small open mouth',(0,.959,.159),(.041,.027,.012),'514052','body',0,mat,8,4)
    bones=[('root',None,(0,0,0)),('body','root',(0,1,0))]
    for side,sign in [('l',-1),('r',1)]:
        bones += [('ear_'+side,'body',(sign*.11,1.16,0)),('wing_'+side+'1','body',(sign*.14,1.06,-.045)),
            ('wing_'+side+'2','wing_'+side+'1',(sign*.305,1.24,-.045)),('foot_'+side,'body',(sign*.075,.82,0))]
    rig=m.skeleton(bones);m.animate(rig,ANIMS,pose)
    m.export(ID,rig,{'radius':.30,'height':1.33,'hurt_point':[0,1.0,.05],'badge_point':[0,1.55,0],
        'hover_center':[0,1.0,0],'anims':ANIMS,'note':'Hover height is in rest pose; fly_high adds no flight-height offset. Movement and blob shadow belong to the consumer.'})


if __name__=='__main__':main()
