"""Coffee Shop adapter data for Zhao Yun's scene_bench contract (39f50fb)."""
def apply(layout):
    b=layout['bench'];b['floor_y']=-.07
    for w in b['route']:
        if w['name']=='entry_inside':w['capture']='door'
        if w['name']=='counter_front':w['capture']='main'
    targets={'counter':'/counter/','table_left':'/table/','large_pot':'/LargeMonsteraLeft/','front_low_wall':'/low_wall_front_left/','side_low_wall':'/low_wall_long/'}
    for p in b['blocked']:
        if 'toward' in p:p['to']=p.pop('toward')
        if p['name'] in targets:p['target']=targets[p['name']]
    b['blocked']=[p for p in b['blocked'] if p['name'] in targets]
    for p in b['blocked']:
        if p['name']=='large_pot':p['from']=[-2.00,.07,-.95]
    b['blocked'] += [
        {'name':'left_arch_boundary','from':[-2.3,.07,1.2],'to':[-3.5,.07,1.2],'target':'left_open_arch_boundary'},
        {'name':'landing_front_boundary','from':[.15,-.20,3.35],'to':[.15,-.2,4.2],'target':'landing_front_edge'},
        {'name':'landing_side_boundary','from':[.15,-.20,3.35],'to':[1.5,-.2,3.35],'target':'landing_right_edge'}]
    measurements={
        'tables_center':([[-.30,.72,.65],[.89,.72,.65]],1.19),
        'tables_counter':([[-1.34,.72,-1.31],[-1.34,.72,-.01]],1.30),
        'entry':([[-.51,.6,2.72],[.81,.6,2.72]],1.32)}
    for gap in b['gaps']:
        gap['measure'],gap['width']=measurements[gap['name']];gap['minimum']=.70
    b['entrance']={'inside':[.15,.07,2.25],'outside':[.15,-.20,3.35]}
    b['slide']={'from':[2.62,.07,.05],'direction':[1,0,-1],'tangent':[0,0,-1],'seconds':.65}
    b['input_start']=[.05,.07,-.65]
    b['scale']={
        'door':{'height':2.69,'source':'Open limestone arch, clear apex 1.93 + 0.76m','reason':'Greenhouse architectural arch is 15.45% taller than Basic Room 2.33m door; preserve reference transom/arch alignment. It is a decorative side arch; usable entrance is the front low-wall gap.'},
        'counter':{'height':1.2005,'source':'Stone worktop top: local 1.12 + 0.07 + pivot .06 - floor .0495'},
        'chair':{'height':.71045,'source':'Seat cushion top (.545 + .070) × 1.13 + pivot .065 - floor .0495'},
        'table':{'height':1.0175,'source':'Tabletop (.79 + .045) × 1.20 + pivot .065 - floor .0495'} }
    b['harness_status']='Adapted to tools/dev/scene_bench at 39f50fb; execution evidence separate'
    light=layout['lighting']
    layout['review_lighting']={'background':light['background'],'ambient_color':light['ambient'],'ambient':light['ambient_energy'],'sun_color':light['sun_color'],'sun':light['sun_energy'],'sun_position':light['sun_position'],'sun_target':light['sun_target'],'points':light['lamps']}
    return layout
