extends "res://tools/art/render_inventory_items.gd"

func _item_ids() -> Array:
	return ["rusty_sword", "copper_sword", "trail_boots"]

func _model(item_id: String) -> Node3D:
	return preload("res://modules/mining/combat_art.gd").model(item_id)
