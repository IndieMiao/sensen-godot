extends "res://review.gd"
var baseline=preload("res://baseline_ground/alc_terrain_detail.tres")
var diagnostic: ShaderMaterial
var neutral: ShaderMaterial
var occlusion: ShaderMaterial
func set_grass(material):
 for n in targets:
  n.material_override = dock if str(n.name).begins_with("Dock") else material
func revision_pair(name):
 set_grass(baseline);await capture(name+"-before")
 set_grass(terrain);await capture(name+"-after")
 set_grass(neutral);await capture(name+"-lighting-control")
 set_grass(diagnostic);await capture(name+"-classes")
 set_grass(occlusion);await capture(name+"-occlusion-control")
 set_grass(terrain)
func run():
 output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
 report.revision="1.1";report.before_commit="91c563b16b651c1013d0290e70d611884376ab0f"
 vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
 vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var display=TextureRect.new();display.texture=vp.get_texture();display.size=Vector2(360,800);add_child(display)
 island=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();vp.add_child(island)
 for i in 16:await get_tree().process_frame
 var waits=0
 while island._rig.is_busy() and waits<600:waits+=1;await get_tree().process_frame
 check(not island._rig.is_busy(),"host avatar assembled")
 island.set_process(false);island._rig.process_mode=Node.PROCESS_MODE_DISABLED;Engine.time_scale=0.0
 camera=island._camera
 for n in island.mesh_nodes:
  if str(n.name).begins_with("AlcGround") or str(n.name).begins_with("Dock"):
   originals[n]=n.material_override;targets[n]=dock if str(n.name).begins_with("Dock") else terrain
 check(targets.size()==4,"same four host meshes")
 diagnostic=terrain.duplicate();diagnostic.shader=load("res://grass_diagnostic.gdshader")
 occlusion=diagnostic.duplicate();occlusion.set_shader_parameter("mask_off",true)
 neutral=terrain.duplicate()
 # Equal grass albedo reveals actual lighting/shadows; no production light edit.
 for key in ["grass_deep_color","grass_base_color","grass_sun_color"]:
  neutral.set_shader_parameter(key,Color("86A84F"))
 neutral.set_shader_parameter("grass_detail_strength",0.0)
 for view in ["opening","mid_hill","summit"]:
  var key="visitor_center" if view=="summit" else view
  island._player.position=island._vec(island.layout.review_points[key]);island._focus=island._follow_target();island._update_camera()
  check(is_equal_approx(camera.size,6.72),view+": original default camera")
  await revision_pair(view)
 island._hud.hide();island._set_backdrop_visible(false)
 vp.size=Vector2i(1100,800);camera.size=9;camera.position=Vector3(-12,17,8);camera.look_at(Vector3(-12,5.5,0));camera.far=300
 await revision_pair("grass_detail")
 report.renderer={"engine":Engine.get_version_info().string,"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
 report.comparison_clock="QA clock frozen only for matched images; original host sea/materials/lighting unchanged"
 report.passed=report.checks.all(func(c):return c.passed)
 FileAccess.open(output+"/render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
 Engine.time_scale=1.0;get_tree().quit(0 if report.passed else 1)
