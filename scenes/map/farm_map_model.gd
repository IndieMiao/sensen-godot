extends Node3D

const Preview = preload("res://scenes/map/farm_miniature.gd")
const Art = preload("res://modules/farm/farm_art.gd")
var model: Node3D
var _key := ""
var _owner := ""
var _pop: Tween

func show_farm(owner: String, region: String, layout: String, plots: int) -> void:
	var style := Art.style_for(region, layout)
	var key := "%s:%d" % [style, plots]
	var changed := _owner != owner or not visible
	if _key != key:
		if model:
			remove_child(model)
			model.queue_free()
		model = Preview.build_model(style, plots)
		add_child(model)
		_key = key
		changed = true
	_owner = owner
	show()
	if changed:
		if _pop: _pop.kill()
		model.scale = Vector3.ONE * 0.05
		_pop = create_tween()
		_pop.tween_property(model, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
