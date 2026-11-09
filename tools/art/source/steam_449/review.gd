extends Node
const Host=preload("res://wait_host.gd")
var host
var steam:GPUParticles3D
var ap:AnimationPlayer
var output:String
var report={"frames":[],"fixture":"Isolated native wait host, canvas expanded to200x220 at80,110; no gameplay integration"}
class Guides extends Control:
	var clock=0.0
	func _draw():
		draw_rect(Rect2(130,110,100,85),Color(.28,.45,.40,.5),false,1)
		draw_line(Vector2(130,170),Vector2(230,170),Color(.32,.45,.30,.3),1)
		draw_arc(Vector2(180,235),60,0,TAU,128,Color("82927A"),1,true)
		draw_arc(Vector2(180,235),46,-1.8,-1.2,32,Color("CFAB55"),5,true)
		var a=clock*TAU/1.4
		draw_line(Vector2(180,235)+Vector2(cos(a),sin(a))*40,Vector2(180,235)+Vector2(cos(a),sin(a))*57,Color("6C6852"),2,true)
func _ready():run.call_deferred()
func label(text,at,size):
	var l=Label.new();l.text=text;l.position=at;l.add_theme_font_size_override("font_size",size);l.add_theme_color_override("font_color",Color("4E645A"));add_child(l)
func run():
	output=OS.get_environment("STEAM_REVIEW");DirAccess.make_dir_recursive_absolute(output+"/frames");DirAccess.make_dir_recursive_absolute(output+"/layers")
	var bg=ColorRect.new();bg.color=Color("F3EBDD");bg.size=Vector2(360,800);add_child(bg)
	var sink=ColorRect.new();sink.color=Color("FAF8F3");sink.position=Vector2(112,132);sink.size=Vector2(170,75);add_child(sink)
	label("SGODOT-449 / particle preview",Vector2(16,32),19)
	label("Cream wall + white sink colour test",Vector2(16,62),15)
	host=Host.new();add_child(host)
	if OS.get_environment("STEAM_HDR")=="1":host.view.use_hdr_2d=true
	if OS.get_environment("STEAM_PREMUL")=="1":
		var mat=CanvasItemMaterial.new();mat.blend_mode=CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA;host._tex.material=mat
	var flat=Vector2(9.5,11.2).normalized();var p=deg_to_rad(43.0);var back=Vector3(flat.x*cos(p),sin(p),flat.y*cos(p))
	var basis=Basis.looking_at(-back,Vector3.UP)
	if OS.get_environment("STEAM_HDR_LINEAR_FIX")=="1":
		var sh=Shader.new();sh.code="shader_type canvas_item; render_mode blend_premul_alpha; void fragment(){vec4 p=texture(TEXTURE,UV);vec3 c=p.rgb/max(p.a,0.00001);c=mix(c*12.92,1.055*pow(max(c,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),c));COLOR=vec4(c*p.a,p.a);}"
		var m=ShaderMaterial.new();m.shader=sh;host._tex.material=m
	host.setup(basis,Basis.IDENTITY,"pot_big",1.0);host.settle();host.visible=true;host.view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	steam=host.pot.find_child("Steam",true,false);steam.visible=true;steam.emitting=true
	if OS.get_environment("STEAM_SINGLE")=="1":steam.amount=1;steam.restart()
	ap=host.pot.get_node("AnimationPlayer");ap.play("tumble")
	var guides=Guides.new();guides.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(guides)
	label("Particle region: x130–230 / y110–195",Vector2(16,350),16)
	label("Mouth (180,235) / 43° / 500 px per m",Vector2(16,378),15)
	label("Native wait-host camera and warm light",Vector2(16,410),14)
	label("Preview only; live integration pending",Vector2(16,730),15)
	for i in 90:await get_tree().process_frame
	report.camera={"basis":[vec(host._cam.basis.x),vec(host._cam.basis.y),vec(host._cam.basis.z)],"position":vec(host._cam.position),"size":host._cam.size,"mouth":vec2(host._cam.unproject_position(Host.mouth_point(host.pot,""))+host.position),"viewport":vec2(host.view.size),"offset":vec2(host.position)}
	report.particles={"amount":steam.amount,"lifetime":steam.lifetime,"interval":steam.lifetime/steam.amount,"quad_m":vec2(steam.draw_pass_1.size)}
	for i in (12 if OS.get_environment("STEAM_SHORT")=="1" else 90):
		guides.clock=i/30.0;guides.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output+"/frames/%03d.png"%i)
		var raw=host.view.get_texture().get_image();raw.convert(Image.FORMAT_RGBA8);raw.save_png(output+"/layers/%03d.png"%i)
		var lid=host.pot.get_node("PotRig/StovePot/pot_big/lid/lid_mesh");var lid_top=INF
		for v in lid.mesh.get_faces():lid_top=minf(lid_top,host._cam.unproject_position(lid.global_transform*v).y+host.position.y)
		report.frames.append({"i":i,"time":i/30.0,"lid_top":lid_top,"lid_cutoff":steam.material_override.get_shader_parameter("lid_top_uv"),"emitter":vec2(host._cam.unproject_position(steam.global_position)+host.position)})
	FileAccess.open(output+"/measurements.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("STEAM449_PREVIEW_COMPLETE ",JSON.stringify(report.camera));get_tree().quit()
func vec(a):return [a.x,a.y,a.z]
func vec2(a):return [a.x,a.y]
