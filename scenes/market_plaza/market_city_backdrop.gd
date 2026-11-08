@tool
extends Node3D
## Replace this node or switch its art variant for another city. No gameplay.
@export_enum("san_francisco","generic") var variant: String="san_francisco"
const FAR="res://assets/landmarks/_shared/far_backdrop/"
var _cards:Array[Node3D]=[]
var _specs:Array=[]
var _built_variant:=""
func _ready() -> void:_build()
func _build() -> void:
	for card in _cards:card.queue_free()
	_cards.clear()
	_specs=[["far_bridge",-2.0,2.6,2.5],["far_city_high",1.2,2.0,2.5],["far_hills_a",0.0,3.8,3.0]] if variant=="san_francisco" else [["far_city_medium",-1.7,2.6,3.0],["far_city_low",2.2,2.5,3.0],["far_hills_b",0.0,3.8,3.0]]
	for spec in _specs:
		var card:Node3D=load(FAR+spec[0]+".glb").instantiate();card.name=spec[0];add_child(card);_cards.append(card)
	if not has_node("SkyCoverage"):
		var sky:=MeshInstance3D.new();sky.name="SkyCoverage";var quad:=QuadMesh.new();quad.size=Vector2(2,2);sky.mesh=quad
		var mat:=ShaderMaterial.new();mat.shader=load("res://assets/rooms/market_plaza/market_sky.gdshader");mat.render_priority=-110
		sky.material_override=mat;sky.extra_cull_margin=100;sky.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(sky)
	_built_variant=variant
func _process(_dt:float) -> void:
	if _built_variant!=variant:_build()
	var cam:=get_viewport().get_camera_3d()
	if cam==null:return
	var vp:=get_viewport().get_visible_rect().size
	var tall:float=cam.size*vp.y/maxf(1,vp.x)
	for i in _cards.size():
		var spec:Array=_specs[i]
		var baseline:float=.31 if i<2 else .32
		_cards[i].global_position=cam.global_position-cam.global_basis.z*30.0+cam.global_basis.x*float(spec[1])+cam.global_basis.y*(.5-baseline)*tall
		_cards[i].scale=Vector3(spec[2],spec[3],1)
