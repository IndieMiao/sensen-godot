def bench(d):
 y=.065;d['spawn']=[-2.42,y,1.43]
 d['bench']={'floor_y':.058,'route':[
 {'name':'entry','position':[-2.40,y,1.40],'capture':'door'},
 {'name':'circle_start','position':[-1.366,y,.946]},
 {'name':'left_rack','position':[-1.82,y,-.15]},
 {'name':'fitting_room','position':[-1.366,y,-1.5]},
 {'name':'mirror','position':[-.27,y,-1.70]},
 {'name':'rear_rack','position':[.826,y,-1.246]},
 {'name':'jewelry','position':[1.43,y,.28],'capture':'main'},
 {'name':'circle_southeast','position':[.826,y,.946]},
 {'name':'circle_front','position':[-.27,y,1.40]},
 {'name':'circle_complete','position':[-1.366,y,.946]}],
 'blocked':[
 {'name':'round_island','from':[-.27,y,1.4],'to':[-.27,y,.3],'target':'/round_display_island/'},
 {'name':'left_clothing_rack','from':[-1.82,y,-1.0],'to':[-2.8,y,-1.0],'target':'/left_gold_rack/'},
 {'name':'jewelry','from':[1.43,y,.65],'to':[2.6,y,.65],'target':'/jewelry_display/'},
 {'name':'tufted_bench','from':[-1.24,y,1.43],'to':[-1.24,y,2.3],'target':'/pink_tufted_bench/'}],
 'gaps':[
 {'name':'island_to_left_rack','from':[-1.84,y,.50],'to':[-1.84,y,-1.25],'measure':[[-2.425,.7,-.15],[-1.44,.7,-.15]],'width':.985,'minimum':.8},
 {'name':'island_to_rear_rack','from':[-.27,y,-1.70],'to':[1.38,y,-1.70],'measure':[[.70,.7,-2.125],[.70,.7,-.804]],'width':1.321,'minimum':.8},
 {'name':'island_to_bench','from':[-1.34,y,1.40],'to':[-.20,y,1.40],'measure':[[-.55,.5,.983],[-.55,.5,1.84]],'width':.857,'minimum':.8}],
 'entrance':{'inside':[-2.40,y,1.40],'outside':[-2.81,y,1.70]},
 'slide':{'from':[1.80,y,.50],'direction':[1,0,1],'tangent':[0,0,1],'seconds':.32},
 'input_start':[-1.82,y,-.15],
 'scale':{'door':{'height':2.46,'source':'Entrance arch 2.13+.33'},'counter':{'height':1.07625,'source':'Jewelry top (.95+.0175)*1.1+.07-.058'},'table':{'height':1.033,'source':'Island top (.7425+.0275)*1.3+.09-.058'},'chair':{'height':.680,'source':'Bench maximum puff ~.668+.07-.058'}}}
