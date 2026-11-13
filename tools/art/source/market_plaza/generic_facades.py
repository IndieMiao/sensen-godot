"""SGODOT-218 generic v2: four neutral row-house prototypes, shared room skeleton.

Godot metres, local floor pivot, facade front +Z. No projecting Victorian bays.
Only roofs, wall finish and small architectural trim vary; layout owns collisions.
"""
PALETTE = {
    'generic_lime': 'D9D5C8', 'generic_sand_v2': 'C6B38C',
    'generic_brick': 'AA7E65', 'generic_graygreen': '969E8B',
    'generic_trim': 'E1D8C4', 'generic_warmgray': 'A79C8B',
    'generic_roof_taupe': '786B5B', 'generic_roof_tile': '926A4B',
    'generic_door': '766951', 'generic_glass': '85918A',
}
SPECS = [
    {'index': 0, 'wall': 'generic_sand_v2', 'roof': 'low_gable', 'roof_color': 'generic_roof_taupe', 'eave_m': 6.0, 'decoration': 'plain_lintel'},
    {'index': 1, 'wall': 'generic_brick', 'roof': 'flat', 'roof_color': 'generic_roof_tile', 'eave_m': 6.4, 'decoration': 'rain_hood'},
    {'index': 2, 'wall': 'generic_graygreen', 'roof': 'hip', 'roof_color': 'generic_roof_taupe', 'eave_m': 6.0, 'decoration': 'blank_plaque'},
    {'index': 3, 'wall': 'generic_lime', 'roof': 'flat', 'roof_color': 'generic_roof_tile', 'eave_m': 6.4, 'decoration': 'plain_lintel'},
]

def build_house(kit, spec):
    i=spec['index']; paint=spec['wall']; eave=spec['eave_m']; roof=spec['roof_color']; trim='generic_trim'
    kit.begin('facade_generic_'+str(i))
    # 8 cm joint between 4 m bays; all roof returns stay within that bay.
    wall_top=eave-.14 if spec['roof']=='flat' else eave
    kit.box('Independent neutral wall',(0,wall_top/2,0),(3.92,wall_top,2.5),paint,.025)
    kit.box('Warm stone plinth',(0,.14,0),(3.94,.28,2.5),'generic_warmgray',.02)
    kit.box('Simple front eave',(0,eave-.06,1.29),(3.96,.12,.18),trim,.018)
    # Only the top zone changes height; doors/windows/stoops/flowerboxes below
    # keep the accepted v1 coordinates and dimensional envelope.
    if spec['roof']=='low_gable':
        peak=6.45
        kit.mesh('Closed low gable roof',[
            (-1.97,eave,-1.25),(1.97,eave,-1.25),(0,peak,-1.25),
            (-1.97,eave,1.25),(1.97,eave,1.25),(0,peak,1.25)],
            [(0,2,1),(3,4,5),(0,3,5,2),(2,5,4,1),(0,1,4,3)],roof)
        kit.mesh('Plain plaster gable',[(-1.91,eave,1.255),(1.91,eave,1.255),(0,peak-.035,1.255)],[(0,1,2)],paint)
        kit.beam('Left gable coping',(-1.95,eave+.015,1.28),(0,peak,1.28),.065,trim,.10)
        kit.beam('Right gable coping',(0,peak,1.28),(1.95,eave+.015,1.28),.065,trim,.10)
    elif spec['roof']=='hip':
        peak=6.45
        kit.mesh('Closed hipped roof',[
            (-1.97,eave,-1.25),(1.97,eave,-1.25),(1.97,eave,1.25),(-1.97,eave,1.25),
            (-.85,peak,0),(.85,peak,0)],
            [(0,4,5,1),(1,5,2),(2,5,4,3),(3,4,0),(0,1,2,3)],roof)
        kit.box('Short independent ridge',(0,peak,0),(1.74,.055,.09),roof,.01)
    else:
        kit.box('Recessed warm roof',(0,eave-.07,0),(3.92,.10,2.5),roof,.01)
        for z in [-1.20,1.20]:kit.box('Low parapet',(0,eave+.03,z),(3.96,.10,.10),paint,.01)
        for x in [-1.93,1.93]:kit.box('Parapet return',(x,eave+.03,0),(.10,.10,2.5),paint,.01)
        kit.box('Front parapet cap',(0,eave+.08,1.20),(3.98,.04,.14),trim,.008)
    # Shared closed door, its frame and the three decorative steps: v1 positions.
    kit.box('Door closed leaf',(0,1.33,1.30),(.98,2.20,.12),'generic_door',.02)
    for x in [-.56,.56]:kit.box('Door surround',(x,1.35,1.36),(.12,2.38,.15),trim,.015)
    kit.box('Door lintel',(0,2.52,1.36),(1.25,.14,.18),trim,.02)
    for y in [.68,1.25]:kit.box('Door inset panel',(0,y,1.372),(.75,.39,.025),'generic_door',.025)
    kit.box('Door transom',(0,2.12,1.38),(.73,.45,.025),'generic_glass',.012)
    kit.ellipsoid('Door knob',(.32,1.25,1.415),(.055,.055,.04),'iron',8,5)
    for j in range(3):kit.box('Decorative step %d'%j,(0,.06+j*.08,1.75-j*.18),(1.36,.12+j*.16,.26),'stone',.02)
    def window(x,y,w,h):
        z=1.30
        kit.box('Flush opaque glass',(x,y,z),(w,h,.06),'generic_glass',.01)
        for xx in [x-w/2-.045,x+w/2+.045]:kit.box('Window jamb',(xx,y,z+.035),(.09,h+.18,.11),trim,.01)
        for yy in [y-h/2-.045,y+h/2+.045]:kit.box('Window rail',(x,yy,z+.04),(w+.18,.09,.13),trim,.01)
        kit.box('Window mullion',(x,y,z+.06),(.045,h,.08),trim,.005)
        kit.box('Window transom',(x,y+.12,z+.06),(w,.045,.08),trim,.005)
        kit.box('Flat window sill',(x,y-h/2-.12,z+.08),(w+.24,.10,.20),trim,.015)
    for x in [-1.25,1.25]:window(x,1.56,.68,1.28)
    for x in [-.86,0,.86]:window(x,4.48,.66,1.46)
    if spec['decoration']=='rain_hood':
        kit.box('Small door rain hood',(0,2.64,1.49),(1.36,.11,.42),roof,.02)
        for x in [-.49,.49]:kit.beam('Hood bracket',(x,2.45,1.29),(x,2.59,1.64),.06,'generic_door')
    elif spec['decoration']=='blank_plaque':
        kit.box('Unlettered plaque frame',(0,2.92,1.33),(.94,.30,.10),'generic_door',.025)
        kit.box('Unlettered plaque face',(0,2.92,1.389),(.82,.20,.025),trim,.015)
    else:
        kit.box('Plain lintel cap',(0,2.65,1.37),(1.36,.10,.20),'generic_warmgray',.018)
    # Mandatory existing flowerbox positions; modest white/ochre blossoms.
    for x,y,z in [(-1.25,.79,1.53),(1.25,.79,1.53),(0,3.43,1.62)]:
        width=.84 if y<1 else 1.5
        kit.box('Window flowerbox',(x,y,z),(width,.24,.30),trim,.025)
        for j in range(5):
            xx=x+(j-2)*width*.17
            kit.ellipsoid('Window foliage',(xx,y+.16,z),(.24,.22,.27),'leaf' if j%2 else 'leaf_light',8,5)
            kit.ellipsoid('Window flower',(xx,y+.285,z+.04),(.14,.07,.14),'petal_white' if j%2 else 'petal_yellow',8,5)
