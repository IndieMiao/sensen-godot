def bench(d):
 y=.06;d['spawn']=[.15,-.20,4.15]
 d['bench']={'floor_y':-.22,'route':[
  {'name':'path','position':[.15,-.20,3.85]}, {'name':'lower_step','position':[.15,-.17,3.23]},
  {'name':'entrance','position':[.15,y,2.18],'capture':'door'}, {'name':'between_tables','position':[0,y,.69]},
  {'name':'counter','position':[0,y,-.33],'capture':'main'}, {'name':'left_tree_bed','position':[-2.00,y,-.33]},
  {'name':'counter_return','position':[0,y,-.33]}, {'name':'right_tree_bed','position':[2.2,y,-.33]},
  {'name':'center_return','position':[0,y,-.33]}, {'name':'door_return','position':[.15,y,2.15]}],
  'blocked':[
  {'name':'counter','from':[0,y,-.28],'to':[0,y,-1.3],'target':'/serving_counter/'},
  {'name':'left_table','from':[-1.45,y,-.25],'to':[-1.45,y,.65],'target':'/round_table/'},
  {'name':'tree_bed','from':[2.35,y,-.55],'to':[2.35,y,-1.8],'target':'/stone_tree_bed_1/'},
  {'name':'stone_wall','from':[2.55,y,0],'to':[3.55,y,0],'target':'/side_low_wall/'},
  {'name':'meadow_edge','from':[.15,-.20,4.17],'to':[.15,-.2,5.3],'target':'meadow_front_limit'},
  {'name':'meadow_side','from':[3.6,-.20,3.35],'to':[4.7,-.2,3.35],'target':'meadow_right_limit'}],
  'gaps':[
  {'name':'chairs_center','from':[0,y,1.80],'to':[0,y,-.26],'measure':[[-.41,.7,.945],[.41,.7,.945]],'width':.82,'minimum':.7},
  {'name':'table_counter','from':[-1.45,y,-.31],'to':[1.60,y,-.31],'measure':[[-1.45,.7,-.74],[-1.45,.7,.10]],'width':.84,'minimum':.7},
  {'name':'entrance','from':[.15,y,2.18],'to':[.15,-.17,3.25],'measure':[[-.77,.6,2.68],[1.08,.6,2.68]],'width':1.85,'minimum':.7}],
  'entrance':{'inside':[.15,y,2.15],'outside':[.15,-.19,3.32]},
  'slide':{'from':[2.60,y,0],'direction':[1,0,-1],'tangent':[0,0,-1],'seconds':.65},
  'input_start':[0,y,-.31],
  'scale':{'door':{'height':2.63,'source':'Side arch clear apex 1.96+.67'},'counter':{'height':1.2005,'source':'Stone worktop 1.1905+.06-.05'},'chair':{'height':.6904,'source':'Wicker seat cushion (.57+.06)*1.08+.06-.05'},'table':{'height':1.03785,'source':'Stone tabletop (.80+.0425)*1.22+.06-.05'}}}
