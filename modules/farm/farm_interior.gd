class_name FarmInterior
extends RefCounted
## The private farm presents the same server cells in an ergonomic three-row garden.
## IDs are translated only at the session boundary; saved blueprints stay authoritative.

var blueprint: FarmBlueprint
var _to_source := {}
var _to_local := {}

func _init(source: FarmBlueprint) -> void:
	blueprint = FarmBlueprint.new()
	for key in ["layout_patch_id", "revision", "region_id", "display_name", "checksum"]:
		blueprint.set(key, source.get(key))
	blueprint.grid = Vector2i(20, 20)
	blueprint.cell_m = 0.65
	blueprint.cell_mm = 650
	blueprint.play_area_m = 13.0
	blueprint.play_area_mm = 13000
	blueprint.overlay = source.overlay.duplicate(true)
	blueprint.anchors = {"spawn": Vector2i(3, 7), "house": Vector2i(6, 12),
		"storage": Vector2i(10, 13), "well": Vector2i(10, 8), "exit": Vector2i(3, 1), "beds": []}
	var all_beds := source.beds().duplicate()
	all_beds.append(source.reserved_bed())
	for row in all_beds.size():
		var bed: Dictionary = all_beds[row]
		var local_bed := {"id": bed.id, "cells": []}
		for column in bed.cells.size():
			var local := Vector2i(4 + column * 2, 8 - row * 2)
			local_bed.cells.append(local)
			var source_id := _id(bed.cells[column])
			_to_source[_id(local)] = source_id
			_to_local[source_id] = _id(local)
		if row < 3: blueprint.anchors.beds.append(local_bed)
		else: blueprint.anchors.reserved_bed = local_bed
	for key in FarmBlueprint.MASK_NAMES: blueprint.masks[key] = []
	for y in blueprint.grid.y:
		var cultivable := ""
		var walkable := ""
		for x in blueprint.grid.x:
			cultivable += "1" if _to_source.has(_id(Vector2i(x, y))) else "0"
			var obstacle := _to_source.has(_id(Vector2i(x, y))) or (x >= 5 and x <= 7 and y >= 11 and y <= 13) or (x == 10 and y in [8, 13])
			walkable += "0" if obstacle else "1"
		blueprint.masks.visual.append("1".repeat(blueprint.grid.x))
		blueprint.masks.walkable.append(walkable)
		blueprint.masks.buildable.append("1".repeat(blueprint.grid.x))
		blueprint.masks.cultivable.append(cultivable)

func local_cells(cells: Dictionary) -> Dictionary:
	var result := {}
	for id in cells:
		if _to_local.has(id): result[_to_local[id]] = cells[id].duplicate(true)
	return result

func local_snapshot(cells: Array) -> Array:
	var result := []
	for cell in cells:
		var id := str(cell.get("cell_id", ""))
		if not _to_local.has(id): continue
		var local: Dictionary = cell.duplicate(true)
		local.cell_id = _to_local[id]
		result.append(local)
	return result

func server_payload(payload: Dictionary) -> Dictionary:
	var result := payload.duplicate(true)
	result.cell_ids = (payload.get("cell_ids", []) as Array).map(func(id): return source_id(str(id)))
	return result

func source_id(local_id: String) -> String:
	return str(_to_source.get(local_id, ""))

static func _id(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]
