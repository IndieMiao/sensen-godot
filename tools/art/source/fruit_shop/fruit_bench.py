def bench(d):
 y=.06;d['spawn']=[.15,y,2.15]
 d['bench']={'floor_y':.05,'route':[
 {'name':'entrance','position':[.15,y,2.14],'capture':'door'},
 {'name':'left_crate_front','position':[-.48,y,1.74]},
 {'name':'left_crate_side','position':[-.48,y,.50]},
 {'name':'produce_table','position':[0,y,-.22],'capture':'main'},
 {'name':'left_olive','position':[-2.1,y,-.22]},
 {'name':'display_return','position':[0,y,-.22]},
 {'name':'right_olive','position':[2.35,y,-.22]},
 {'name':'right_crate','position':[2.18,y,1.55]},
 {'name':'front_return','position':[2.12,y,2.18]},
 {'name':'entrance_return','position':[.15,y,2.18]}],
 'blocked':[
 {'name':'produce_counter','from':[0,y,-.18],'to':[0,y,-1.3],'target':'/produce_display_table/'},
 {'name':'floor_crate','from':[-1.36,y,.21],'to':[-1.36,y,1.20],'target':'/floor_orange_crate/'},
 {'name':'olive_pot','from':[-1.7,y,1.13],'to':[-2.6,y,1.13],'target':'LeftOlive'},
 {'name':'side_wall','from':[2.5,y,.15],'to':[3.6,y,.15],'target':'/side_low_wall/'}],
 'gaps':[
 {'name':'crate_to_counter','from':[-2.0,y,-.04],'to':[1.7,y,-.04],'measure':[[-1.36,.32,-.855],[-1.36,.32,.75]],'width':1.605,'minimum':.8},
 {'name':'entrance','from':[.15,y,2.18],'to':[.15,-.17,3.26],'measure':[[-.77,.6,2.68],[1.08,.6,2.68]],'width':1.85,'minimum':.7}],
 'entrance':{'inside':[.15,y,2.15],'outside':[.15,-.19,3.32]},
 'slide':{'from':[-2.60,y,-1.24],'direction':[-1,0,-1],'tangent':[0,0,-1],'seconds':.35},
 'input_start':[0,y,.25],
 'scale':{'door':{'height':2.63,'source':'Side arch 1.96+.67'},'counter':{'height':1.01,'source':'Produce worktop .94+.06+.06-.05'},'chair':{'height':.685,'reason':'No chair in reference; baseline placeholder, not an invented prop.'},'table':{'height':1.01,'source':'Produce display table is the only table in this shop.'}}}
