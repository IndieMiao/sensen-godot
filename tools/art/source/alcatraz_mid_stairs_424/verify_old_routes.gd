extends SceneTree
func _initialize():
 var l:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ALC_LAYOUT")))
 var map=NavigationServer3D.map_create();NavigationServer3D.map_set_active(map,true);NavigationServer3D.map_set_cell_size(map,.25);NavigationServer3D.map_set_cell_height(map,.1)
 var vertices=PackedVector3Array()
 for v in l.navigation.vertices:vertices.append(Vector3(v[0],v[1],v[2]))
 var regions:Array=[]
 for zone in l.zones:
  var mesh=NavigationMesh.new();mesh.vertices=vertices;mesh.cell_size=.25;mesh.cell_height=.1
  for poly in l.navigation.zone_polygons[zone]:mesh.add_polygon(PackedInt32Array(poly))
  var region=NavigationRegion3D.new();region.navigation_mesh=mesh;root.add_child(region);region.set_navigation_map(map);regions.append(region)
 for i in 15:await physics_frame
 var checks=[]
 for pair in [[Vector3(-22,1,12),Vector3(-22,3.25,7.5)],[Vector3(8,3.25,7.5),Vector3(8,5.5,3)],[Vector3(-22,5.5,3),Vector3(-22,7.75,-1.5)],[Vector3(8,7.75,-1.5),Vector3(8,10,-6)]]:
  var paths=[]
  for endpoints in [pair,[pair[1],pair[0]]]:
   var path=NavigationServer3D.map_get_path(map,endpoints[0],endpoints[1],true);var length=0.0;var minx=INF;var maxx=-INF
   for i in path.size():
    minx=minf(minx,path[i].x);maxx=maxf(maxx,path[i].x)
    if i>0:length+=path[i].distance_to(path[i-1])
   paths.append({"length":length,"x_range":[minx,maxx],"end_error":path[-1].distance_to(endpoints[1]) if path.size()>0 else 999.0})
  checks.append({"lower":[pair[0].x,pair[0].y,pair[0].z],"upper":[pair[1].x,pair[1].y,pair[1].z],"directions":paths})
 var old_legs=[];var original:Array=l.mid_stairs.original_route
 for i in range(1,original.size()):
  var a=Vector3(original[i-1][0],original[i-1][1],original[i-1][2]);var b=Vector3(original[i][0],original[i][1],original[i][2]);var path=NavigationServer3D.map_get_path(map,a,b,true)
  old_legs.append({"leg":i,"end_error":path[-1].distance_to(b) if path.size()>0 else 999.0,"points":path.size()})
 FileAccess.open(OS.get_environment("ALC_ROUTE_OUT"),FileAccess.WRITE).store_string(JSON.stringify({"flights":checks,"original_route_legs":old_legs},"  "))
 print("OLD_FLIGHTS ",checks)
 for region in regions:region.queue_free()
 NavigationServer3D.free_rid(map);quit()
