def bench(d):
 y=.06;d['spawn']=[.15,y,2.14]
 d['bench']={'floor_y':.05,'route':[
 {'name':'entrance','position':[.15,y,2.15],'capture':'door'},
 {'name':'aisle_between','position':[.42,y,1.10]},
 {'name':'checkout','position':[.42,y,-.50],'capture':'main'},
 {'name':'refrigerator','position':[-1.90,y,-.50]},
 {'name':'checkout_return','position':[.42,y,-.50]},
 {'name':'freezer','position':[2.0,y,-.36]},
 {'name':'aisle_return','position':[.42,y,-.31]},
 {'name':'island_center','position':[.42,y,1.12]},
 {'name':'entrance_return','position':[.15,y,2.15]}],
 'blocked':[
 {'name':'checkout','from':[.3,y,-.5],'to':[.3,y,-1.5],'target':'/checkout/'},
 {'name':'produce_island','from':[-1.2,y,1.20],'to':[-1.2,y,.20],'target':'/produce_aisle/'},
 {'name':'essentials_island','from':[.5,y,1.20],'to':[1.45,y,1.20],'target':'/essentials_aisle/'},
 {'name':'freezer','from':[2.0,y,-.27],'to':[2.0,y,-1.3],'target':'/ice_cream_freezer/'},
 {'name':'fridge','from':[-1.85,y,-.72],'to':[-2.8,y,-.72],'target':'/drink_cabinet/'},
 {'name':'side_wall','from':[2.6,y,1.3],'to':[3.6,y,1.3],'target':'/side_low_wall/'}],
 'gaps':[
 {'name':'two_islands','from':[.42,y,1.55],'to':[.42,y,-.50],'measure':[[-.23,.7,.35],[1.135,.7,.35]],'width':1.365,'minimum':.7},
 {'name':'checkout_island','from':[-1.80,y,-.52],'to':[.42,y,-.52],'measure':[[-1.19,.7,-1.06],[-1.19,.7,-.065]],'width':.995,'minimum':.7},
 {'name':'entrance','from':[.15,y,2.18],'to':[.15,-.17,3.26],'measure':[[-.77,.6,2.68],[1.08,.6,2.68]],'width':1.85,'minimum':.7}],
 'entrance':{'inside':[.15,y,2.15],'outside':[.15,-.19,3.32]},
 'slide':{'from':[-.9,y,-.81],'direction':[1,0,-1],'tangent':[1,0,0],'seconds':.50},
 'input_start':[.42,y,.8],
 'scale':{'door':{'height':2.44,'source':'Rectangular entrance jamb'},'counter':{'height':1.1025,'source':'Checkout top 1.035+.0575+.06-.05'},'chair':{'height':.685,'reason':'No seating in this shop reference; baseline placeholder only.'},'table':{'height':1.1025,'source':'Checkout counter is the customer tabletop.'}}}
