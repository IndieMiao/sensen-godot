class_name MapAvatarPopup
extends Node3D
## Animate the model around its feet, independently of map camera scale/position.
var animation: Tween
var started := false

func pop() -> void:
	if started: return
	started = true
	scale = Vector3(0.32, 0.08, 0.32)
	animation = create_tween()
	animation.tween_property(self, "scale", Vector3(0.86, 1.15, 0.86), 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.tween_property(self, "scale", Vector3(1.12, 0.88, 1.12), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	animation.tween_property(self, "scale", Vector3(0.97, 1.04, 0.97), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	animation.tween_property(self, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
