class_name PondScenery
extends Node3D
## Static, seeded scenery shared by entry previews and playable ponds.
var _rng := RandomNumberGenerator.new()
const Art = preload("res://modules/farm/farm_art.gd")
const FarmCamera = preload("res://modules/farm/farm_camera.gd")
## The decorated meadow (x, z): the turf pile covers it, flowers and trees sit inside; past it the bank ground runs on
## plain. The P0 pond camera keeps the screen on it (不知火舞 on 231).
const MEADOW := Rect2(-3, -19, 18, 21)

## `clear`: world points (a pond's gathering pieces, SGODOT-410) its trees and bushes keep CLEAR_M off — a tree also
## stays out of the strip in front of one (FRONT_M toward the camera, FRONT_HALF_W a side), where its crown would
## cover it; the draws are the same either way, so the rest of the bank stays where it was.
const CLEAR_M := 1.5
const FRONT_M := 4.0
const FRONT_HALF_W := 2.0
static func build(entry: Dictionary, clear: Array = [], in_key := Callable()) -> PondScenery:
	var scene := PondScenery.new()
	scene.name = "Scenery"
	scene._rng.seed = int(entry.decoration_seed)
	var spec := SystemPonds.site(entry)
	# the wild's painted ground and its bank rocks (SGODOT-422 v7, 盘古); the ground deepens under the bank's trees
	var trees := tree_points(clear, in_key)
	var ground := PondWildGround.build(entry, spec, clear, trees)
	scene.add_child(ground)
	# The bank's six trees are the wild's single pines and round trees (SGODOT-422 ⑥), placed with the rest of the wild's
	# pieces (PondWildProps, PondWildGround.regroup turns them into the pack's trees); their trunks block the P0 walk
	# (PondWalk.set_trees), which reaches them since q(297). The old soft grass tufts are not drawn on the painted ground
	# (the user on the v1 sample: no grass piles back), nor the turf pile and the spawn's crumbs.
	var props := PondWildProps.build(entry, spec, clear, trees, in_key)
	scene.add_child(props)
	var rocks := ground.find_child("BankRockGroups", false, false)
	scene._foam = {"extent": Vector2(spec.extent[0], spec.extent[1]) if spec.has("extent") else Vector2.ZERO,
		"distances": ground.get_meta("water_distances", PackedFloat32Array()), "rocks": rocks.get_meta("contacts", []) if rocks else [],
		"reeds": props.get_meta("reeds", []), "seed": int(entry.decoration_seed), "outline": (spec.get("polygon", []) as Array).size()}
	var painted := scene.find_child("PaintedGround", true, false) as MeshInstance3D
	if painted:   # the ground darkens a little under the plants' feet, now that they are placed
		(painted.material_override as ShaderMaterial).set_shader_parameter("contact_points", PondWildGround.contact_points())
		(painted.material_override as ShaderMaterial).set_shader_parameter("contact", 0.10)
	return scene

## The water's shore foam (pond_water.gdshader's foam_contact) for this bank as it stands — its waterline, rock groups
## and cattails (PondWildFoam; SGODOT-422, the user's 0.3.5: the old mask's foam stood where the round stones were).
## Made on the first ask (a preview never asks), the same texture after; null when the pond has no outline (fewer than
## FOAM_OUTLINE points: no water to measure from, and the texture would be froth all over — 周瑜 on #942).
const FOAM_OUTLINE := 8
var _foam := {}
var _foam_texture: ImageTexture
func foam_contact() -> ImageTexture:
	if _foam_texture == null and _foam.get("extent", Vector2.ZERO) != Vector2.ZERO and not (_foam.distances as PackedFloat32Array).is_empty() \
			and int(_foam.get("outline", 0)) >= FOAM_OUTLINE:
		_foam_texture = PondWildFoam.build(_foam.extent, _foam.distances, _foam.rocks, _foam.reeds, _foam.seed)
	return _foam_texture

## The wild ground (SGODOT-422, 刘备 #791 / #798): the meadow's colour over the bank's dry ground, the pond's shape's
## layout (crescent / gourd / meander; another shape: none) and its channel of the shared dry-ground mask.
const PondWildProps := preload("res://modules/ponds/pond_wild_props.gd")
const PondWildGround := preload("res://modules/ponds/pond_wild_ground.gd")
const PondWildFoam := preload("res://modules/ponds/pond_wild_foam.gd")
const GROUND_DIR := "res://assets/ponds/ground/"
const DRY_CHANNEL := {"crescent": Vector3(1, 0, 0), "gourd": Vector3(0, 1, 0), "meander": Vector3(0, 0, 1)}
static func _wild_ground(material: ShaderMaterial, shape: String) -> void:
	var layout := GROUND_DIR + shape + "_layout.png"
	if not DRY_CHANNEL.has(shape) or not ResourceLoader.exists(layout):
		material.set_shader_parameter("dry_channel", Vector3.ZERO)   # the ground as it was
		return
	material.set_shader_parameter("meadow_color", load(GROUND_DIR + "meadow_color.png"))
	material.set_shader_parameter("ground_layout", load(layout))
	material.set_shader_parameter("dry_ground_mask", load(GROUND_DIR + "dry_ground_mask.png"))
	material.set_shader_parameter("dry_channel", DRY_CHANNEL[shape])

const TREES := [Vector3(0.1, 0, -4), Vector3(-0.2, 0, -11), Vector3(2.2, 0, -16.1), Vector3(9.5, 0, -16.4), Vector3(12.2, 0, -12), Vector3(12.1, 0, -5.5)]
## The bank's trees that stand: those clear of the gathering points `clear` (CLEAR_M off, out of the strip in front),
## and with `in_key` (PondWildProps.layout's) off the opening screen's action keys.
static func tree_points(clear: Array = [], in_key := Callable()) -> Array:
	return TREES.filter(func(point): return not _near(point, clear) and not _in_front(point, clear) \
		and not (in_key.is_valid() and _tree_under_keys(point, in_key)))

## A bank tree whose crown would stand on the opening screen's action keys (盘古 on 422): it does not stand — its point
## is fixed (its trunk blocks the walk), so it is left out rather than moved. Either kind, at its largest.
static func _tree_under_keys(point: Vector3, in_key: Callable) -> bool:
	for asset in PondWildProps.TREES:
		if bool(in_key.call(PondWildProps.box_corners(asset, point, 1.1))): return true
	return false

static func _near(point: Vector3, clear: Array) -> bool:
	for c in clear:
		if Vector2(point.x - (c as Vector3).x, point.z - (c as Vector3).z).length() < CLEAR_M: return true
	return false

## A tree here would stand between the camera and one of `clear`.
static func _in_front(point: Vector3, clear: Array) -> bool:
	for c in clear:
		var d := point - (c as Vector3)
		var yaw := deg_to_rad(FarmCamera.YAW_DEG)   # the pond's camera turns as the farm's (442): "in front" along its axes
		var toward := d.x * sin(yaw) + d.z * cos(yaw)   # toward the camera on the ground
		if toward > 0.0 and toward <= FRONT_M and absf(d.x * cos(yaw) - d.z * sin(yaw)) < FRONT_HALF_W: return true
	return false
