extends RefCounted
## Schema 4 is a display/permission model, never a gameplay command or a generator.
const MAX_AXIS := 544
const MAX_CELLS := 8192
const SURFACES := ["soil", "grass", "path"]
const ACTIONS := ["walk", "till", "plant", "arrange", "place"]

static func decode(data: Dictionary) -> Dictionary:
	if not integer(data.get("schema")) or int(data.schema) != 4:
		return invalid("Unsupported dynamic farm data version.")
	for key in ["dataset_version", "block_id", "parcel_id", "name", "generator_version"]:
		if not data.get(key) is String or data[key].strip_edges().is_empty() or data[key].length() > 160:
			return invalid("Dynamic farm details are missing.")
	if data.get("selection_unit") != "parcel" or data.block_id != "p-" + data.parcel_id:
		return invalid("Dynamic farm parcel is inconsistent.")
	if data.get("address") != null and (not data.address is String or data.address.length() > 160):
		return invalid("Dynamic farm address is invalid.")
	if not number(data.get("game_cell_m")) or not is_equal_approx(float(data.game_cell_m), 0.8):
		return invalid("Dynamic farm cell scale is invalid.")
	for key in ["source_area_m2", "source_cell_m"]:
		if not number(data.get(key)) or float(data[key]) <= 0.0:
			return invalid("Dynamic farm area or scale is invalid.")
	if not data.get("seed_hex") is String or RegEx.create_from_string("^[0-9a-f]{64}$").search(data.seed_hex) == null:
		return invalid("Dynamic farm seed is invalid.")
	var transform_data = data.get("source_transform")
	if not transform_data is Dictionary or not number(transform_data.get("rotation_deg")):
		return invalid("Dynamic farm orientation is missing.")
	var grid = data.get("grid")
	if not grid is Dictionary:
		return invalid("Dynamic farm grid is missing.")
	for key in ["width", "height"]:
		if not integer(grid.get(key)) or grid[key] < 1 or grid[key] > MAX_AXIS:
			return invalid("Dynamic farm grid exceeds its budget.")
	if not coordinate(grid.get("origin_cell")):
		return invalid("Dynamic farm origin is invalid.")
	var size := Vector2i(int(grid.width), int(grid.height))
	var palette_result := _palette(data.get("surface_palette"))
	if not palette_result.ok:
		return palette_result
	var zones = data.get("zones")
	var caps = data.get("capabilities")
	if not zones is Dictionary or not caps is Dictionary:
		return invalid("Dynamic farm zones or permissions are missing.")
	var cells: Array = []
	var by_cell := {}
	var counts := {"core": 0, "extension": 0}
	for zone in ["core", "extension"]:
		if not zones.get(zone) is Dictionary or not caps.get(zone) is Dictionary:
			return invalid("Dynamic farm zones or permissions are missing.")
		for action in ACTIONS:
			var expected: bool = zone == "core" or action == "walk"
			if not caps[zone].get(action) is bool or caps[zone][action] != expected:
				return invalid("Dynamic farm permissions are inconsistent.")
		var runs = zones[zone].get("runs")
		if not runs is Array or runs.is_empty() or runs.size() > MAX_CELLS:
			return invalid("Dynamic farm zone rows are invalid.")
		var last_y := -1
		var last_end := -1
		for run in runs:
			if not _run_valid(run, size, 4):
				return invalid("Dynamic farm zone row is outside the grid.")
			var y := int(run[0])
			var x := int(run[1])
			var length := int(run[2])
			var surface := int(run[3])
			if y < last_y or (y == last_y and x < last_end) or surface < 0 or surface >= SURFACES.size():
				return invalid("Dynamic farm rows overlap or are unsorted.")
			if cells.size() + length > MAX_CELLS:
				return invalid("Dynamic farm cell budget exceeded.")
			for offset in length:
				var at := Vector2i(x + offset, y)
				if by_cell.has(at):
					return invalid("Core and extension overlap.")
				var cell := {"x": at.x, "y": at.y, "kind": SURFACES[surface], "surface_id": surface, "zone": zone}
				cells.append(cell)
				by_cell[at] = cell
			counts[zone] += length
			last_y = y
			last_end = x + length
	if counts.core < 760 or counts.core > 840:
		return invalid("Dynamic farm core cell count is invalid.")
	var declared = data.get("counts")
	if not declared is Dictionary:
		return invalid("Dynamic farm counts are missing.")
	for pair in [["core_cell_count", counts.core], ["extension_cell_count", counts.extension], ["total_cell_count", cells.size()]]:
		if not integer(declared.get(pair[0])) or int(declared[pair[0]]) != pair[1]:
			return invalid("Dynamic farm counts do not match the cells.")
	if not _connected(by_cell):
		return invalid("Dynamic farm walking area is disconnected.")
	var reserve := _reserve(data.get("walk_reserve"), size, by_cell)
	if not reserve.ok:
		return reserve
	if not _boundaries_valid(data.get("boundaries"), size):
		return invalid("Dynamic farm boundary is invalid.")
	var title: String = data.name.strip_edges()
	var address: String = data.address.strip_edges() if data.get("address") is String else ""
	if title.to_upper() in ["UNKNOWN", "0 UNKNOWN"]:
		title = "SF Parcel " + data.parcel_id
	if address.to_upper() in ["UNKNOWN", "0 UNKNOWN"]:
		address = ""
	return {"ok": true, "schema": 4, "dataset_version": data.dataset_version,
		"block_id": data.block_id, "parcel_id": data.parcel_id, "name": title, "address": address,
		"area_m2": float(data.source_area_m2), "source_area_m2": float(data.source_area_m2),
		"cell_m": float(data.game_cell_m), "grid_size": size,
		"origin": Vector2i(int(grid.origin_cell[0]), int(grid.origin_cell[1])),
		"rotation_deg": float(transform_data.rotation_deg), "seed_hex": data.seed_hex,
		"generator_version": data.generator_version, "cells": cells, "by_cell": by_cell,
		"counts": counts, "palette": palette_result.palette, "capabilities": caps.duplicate(true),
		"protected": reserve.protected, "spawn": reserve.spawn, "entry": reserve.entry,
		"boundaries": data.boundaries.duplicate(true)}

static func world_position(decoded: Dictionary, cell: Vector2i) -> Vector3:
	var at: Vector2i = decoded.origin + cell
	return Vector3((at.x + 0.5) * decoded.cell_m, 0, -(at.y + 0.5) * decoded.cell_m)

static func permits(decoded: Dictionary, cell: Vector2i, action: String) -> bool:
	if not decoded.get("ok", false) or not decoded.by_cell.has(cell) or action not in ACTIONS:
		return false
	return decoded.capabilities[decoded.by_cell[cell].zone][action]

static func _palette(raw: Variant) -> Dictionary:
	if not raw is Array or raw.size() != SURFACES.size():
		return invalid("Dynamic farm surface palette is invalid.")
	var palette := {}
	for item in raw:
		if not item is Dictionary or not integer(item.get("id")) or item.id < 0 or item.id >= SURFACES.size():
			return invalid("Dynamic farm surface is invalid.")
		var kind: String = SURFACES[int(item.id)]
		if palette.has(kind) or not item.get("color") is String or not Color.html_is_valid(item.color):
			return invalid("Dynamic farm surface color is invalid.")
		var color := Color.html(item.color)
		color.a = 1.0
		palette[kind] = color
	return {"ok": true, "palette": palette}

static func _run_valid(run: Variant, size: Vector2i, fields: int) -> bool:
	if not run is Array or run.size() != fields:
		return false
	for value in run:
		if not integer(value):
			return false
	return run[0] >= 0 and run[0] < size.y and run[1] >= 0 and run[2] > 0 and run[1] < size.x and run[2] <= size.x - run[1]

static func _reserve(raw: Variant, size: Vector2i, by_cell: Dictionary) -> Dictionary:
	if not raw is Dictionary or not raw.get("no_solid_decor_runs") is Array or raw.no_solid_decor_runs.size() > MAX_CELLS:
		return invalid("Dynamic farm walking reserve is missing.")
	var protected := {}
	var last_y := -1
	var last_end := -1
	for run in raw.no_solid_decor_runs:
		if not _run_valid(run, size, 3) or run[0] < last_y or (run[0] == last_y and run[1] < last_end):
			return invalid("Dynamic farm walking reserve rows are invalid.")
		for offset in int(run[2]):
			var at := Vector2i(int(run[1]) + offset, int(run[0]))
			if not by_cell.has(at):
				return invalid("Dynamic farm walking reserve leaves the ground.")
			protected[at] = true
		last_y = int(run[0])
		last_end = int(run[1] + run[2])
	var anchors := {}
	for key in ["spawn_cell", "entry_cell"]:
		if not coordinate(raw.get(key)):
			return invalid("Dynamic farm entry is invalid.")
		var at := Vector2i(int(raw[key][0]), int(raw[key][1]))
		if not by_cell.has(at) or not protected.has(at):
			return invalid("Dynamic farm entry has no protected ground.")
		anchors[key] = at
	return {"ok": true, "protected": protected, "spawn": anchors.spawn_cell, "entry": anchors.entry_cell}

static func _boundaries_valid(raw: Variant, size: Vector2i) -> bool:
	if not raw is Dictionary:
		return false
	var points := 0
	for key in ["core", "outer"]:
		if not raw.get(key) is Array or raw[key].is_empty() or raw[key].size() > MAX_CELLS:
			return false
		for polygon in raw[key]:
			if not polygon is Dictionary or not polygon.get("holes") is Array or polygon.holes.size() > MAX_CELLS:
				return false
			var rings: Array = [polygon.get("outer")]
			rings.append_array(polygon.holes)
			for ring in rings:
				if not ring is Array or ring.size() < 4:
					return false
				points += ring.size()
				if points > 65536 or ring[0] != ring[-1]:
					return false
				for point in ring:
					if not point is Array or point.size() != 2 or not number(point[0]) or not number(point[1]):
						return false
					if point[0] < 0 or point[1] < 0 or point[0] > size.x or point[1] > size.y:
						return false
	return true

static func _connected(by_cell: Dictionary) -> bool:
	var seen := {}
	var queue: Array[Vector2i] = [by_cell.keys()[0]]
	seen[queue[0]] = true
	var cursor := 0
	while cursor < queue.size():
		var at := queue[cursor]
		cursor += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = at + offset
			if by_cell.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == by_cell.size()

static func coordinate(value: Variant) -> bool:
	return value is Array and value.size() == 2 and integer(value[0]) and integer(value[1]) and absf(float(value[0])) <= 2147483647 and absf(float(value[1])) <= 2147483647

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func integer(value: Variant) -> bool:
	return number(value) and float(value) == floorf(float(value))

static func invalid(message: String) -> Dictionary:
	return {"ok": false, "error": message}
