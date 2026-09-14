extends RefCounted

const Art = preload("res://modules/farm/farm_art.gd")

static func build(kind: String, position: Vector3, scale: float = 1.0, style := "cottage") -> MeshInstance3D:
	var asset := kind
	if kind == "house":
		asset = "house_" + (style if style in Art.STYLES else "cottage")
	var node := Art.instance(asset, position, scale)
	node.name = kind.capitalize()
	return node
