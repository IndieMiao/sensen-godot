def bench(d):
 y=.065;d['spawn']=[.27,y,2.61]
 d['bench']={'floor_y':.0535,'route':[
 {'name':'stool_gap','position':[.27,y,2.16],'capture':'door'},
 {'name':'front_lane','position':[.27,y,2.61]},
 {'name':'bar_left_end','position':[-1.36,y,2.61]},
 {'name':'counter_corner','position':[-1.36,y,.84]},
 {'name':'order_position','position':[.22,y,.84],'capture':'main'},
 {'name':'right_aisle','position':[2.38,y,.84]},
 {'name':'pickup_approach','position':[2.38,y,-1.18]},
 {'name':'pickup_window','position':[1.08,y,-1.44]},
 {'name':'right_return','position':[2.38,y,-1.18]}],
 'blocked':[
 {'name':'order_counter','from':[.22,y,.84],'to':[.22,y,.2],'target':'/red_order_counter/'},
 {'name':'dining_bar','from':[.22,y,.84],'to':[.22,y,1.49],'target':'/customer_bar/'},
 {'name':'fridge','from':[-1.25,y,-.93],'to':[-1.25,y,-2.28],'target':'/drinks_fridge/'},
 {'name':'planter','from':[-1.90,y,2.24],'to':[-3,y,2.24],'target':'/wood_planter_barrier/'},
 {'name':'stool','from':[.27,y,2.08],'to':[-.36,y,2.08],'target':'/red_diner_stool/'}],
 'gaps':[
 {'name':'counter_to_bar','from':[-1.36,y,.84],'to':[2.38,y,.84],'measure':[[.22,.70,.41],[.22,.70,1.275]],'width':.865,'minimum':.8},
 {'name':'left_bar_access','from':[-1.36,y,2.25],'to':[-1.36,y,.84],'measure':[[-1.90,.7,1.3],[-.965,.7,1.3]],'width':.935,'minimum':.8},
 {'name':'stools_entry','from':[.27,y,2.61],'to':[.27,y,1.98],'measure':[[-.10,.7,2.08],[.65,.7,2.08]],'width':.75,'minimum':.7}],
 'entrance':{'inside':[.27,y,2.31],'outside':[.27,y,2.63]},
 'slide':{'from':[.22,y,.84],'direction':[1,0,-1],'tangent':[1,0,0],'seconds':.4},
 'input_start':[.22,y,.84],
 'scale':{'door':{'height':2.33,'reason':'Open front diorama, no enclosing door; unchanged baseline placeholder.'},'counter':{'height':1.1615,'source':'Counter top 1.08+.075+.06-.0535'},'table':{'height':1.2015,'source':'Bar top 1.13+.065+.06-.0535'},'chair':{'height':.9015,'reason':'High diner stools paired with 1.2015 m bar: seat is 75% of bar height. Explicit high-stool exception in director feedback, not a changed Basic Room baseline.'}}}
