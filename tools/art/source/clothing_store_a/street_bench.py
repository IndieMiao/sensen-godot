def bench(d):
 y=.065;d['spawn']=[-2.42,y,1.43]
 d['bench']={'floor_y':.058,'route':[
 {'name':'entry','position':[-2.40,y,1.40],'capture':'door'},
 {'name':'front_left','position':[-2.02,y,1.40]},
 {'name':'left_edge','position':[-2.02,y,-.24]},
 {'name':'fitting_room','position':[-1.35,y,-1.40]},
 {'name':'mirror','position':[-1.35,y,-1.07]},
 {'name':'checkout','position':[.20,y,-1.14],'capture':'main'},
 {'name':'back_right','position':[1.82,y,-1.10]},
 {'name':'right_edge','position':[1.82,y,.30]},
 {'name':'front_right','position':[1.80,y,1.44]},
 {'name':'complete_circle','position':[-2.02,y,1.40]}],
 'blocked':[
 {'name':'table','from':[0,y,1.44],'to':[0,y,.2],'target':'/central_display_table/'},
 {'name':'left_rack','from':[-2.01,y,-.5],'to':[-2.8,y,-.5],'target':'/street_left_rack/'},
 {'name':'checkout','from':[0,y,-1.10],'to':[0,y,-2.1],'target':'/black_checkout/'},
 {'name':'bench','from':[-1.35,y,1.44],'to':[-1.35,y,2.5],'target':'/black_tufted_bench/'}],
 'gaps':[
 {'name':'table_to_bench','from':[-1.35,y,1.44],'to':[1.80,y,1.44],'measure':[[-.82,.6,.83],[-.82,.6,2.045]],'width':1.215,'minimum':.8},
 {'name':'table_to_right_rack','from':[1.82,y,-1.55],'to':[1.82,y,.5],'measure':[[1.15,.7,-2.105],[1.15,.7,-.51]],'width':1.595,'minimum':.8},
 {'name':'table_to_checkout','from':[-1.25,y,-1.12],'to':[1.82,y,-1.12],'measure':[[0,.7,-1.73],[0,.7,-.51]],'width':1.22,'minimum':.8}],
 'entrance':{'inside':[-2.40,y,1.40],'outside':[-2.81,y,1.70]},
 'slide':{'from':[0,y,-1.14],'direction':[1,0,-1],'tangent':[1,0,0],'seconds':.38},
 'input_start':[0,y,-1.14],
 'scale':{'door':{'height':2.46,'source':'Entrance arch 2.13+.33'},'counter':{'height':1.202,'source':'Counter 1.13+.06+.07-.058'},'table':{'height':1.01255,'source':'Table (.865+.0415)*1.085+.087-.058'},'chair':{'height':.682,'source':'Bench .57+.10+.07-.058'}}}
