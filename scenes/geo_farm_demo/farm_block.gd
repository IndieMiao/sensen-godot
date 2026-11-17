extends RefCounted
## Decoder for the generated schemas v1/v2. Never creates cells or guesses land use.
const KINDS := ["unknown", "residential", "mixed", "public", "green", "water", "path", "commercial", "building"]
const MAX_AXIS := 256
const MAX_CELLS := 4096

static func decode(data: Dictionary) -> Dictionary:
	var schema = data.get("schema")
	if not _integer(schema) or int(schema) not in [1, 2]:
		return _invalid("Unsupported farm data version.")
	for key in ["block_id", "name", "dataset_version"]:
		if not data.get(key) is String or data[key].strip_edges().is_empty() or data[key].length() > 160:
			return _invalid("Farm details are missing.")
	for key in ["source_area_m2", "inset_area_m2"]:
		if not _number(data.get(key)) or float(data[key]) <= 0.0 or float(data[key]) > 1.0e10:
			return _invalid("Farm area is invalid.")
	if int(schema) == 2:
		if data.get("selection_unit") != "parcel" or not data.get("parcel_id") is String or data.parcel_id.is_empty():
			return _invalid("Parcel details are missing.")
		if not _number(data.get("inset_m")) or float(data.inset_m) != 0.0:
			return _invalid("Parcel boundary is invalid.")
		if data.get("address") != null and (not data.address is String or data.address.length() > 160):
			return _invalid("Parcel address is invalid.")
	var grid = data.get("grid")
	if not grid is Dictionary:
		return _invalid("Farm grid is missing.")
	for key in ["width", "height"]:
		if not _integer(grid.get(key)) or grid[key] < 1 or grid[key] > MAX_AXIS:
			return _invalid("Farm grid size is invalid.")
	var raw = grid.get("cells")
	if not raw is Array or raw.is_empty() or raw.size() > MAX_CELLS:
		return _invalid("Farm cells are missing or invalid.")
	var materials = data.get("materials")
	if not materials is Array or materials.is_empty() or materials.size() > KINDS.size():
		return _invalid("Farm surfaces are missing.")
	var palette := {}
	for material in materials:
		if not material is Dictionary or not _integer(material.get("id")):
			return _invalid("Farm surfaces are invalid.")
		var id := int(material.id)
		if id < 0 or id >= KINDS.size() or (int(schema) == 1 and id == 8) or palette.has(KINDS[id]):
			return _invalid("Farm surfaces are invalid.")
		var color = material.get("color")
		if not color is String or not Color.html_is_valid(color):
			return _invalid("Farm surface colors are invalid.")
		var parsed := Color.html(color)
		parsed.a = 1.0
		palette[KINDS[id]] = parsed
	var seen := {}
	var cells: Array = []
	var counts := {"house": 0, "yard": 0, "water": 0, "path": 0}
	for cell in raw:
		if not cell is Array or cell.size() != 3:
			return _invalid("Farm cells are invalid.")
		for value in cell:
			if not _integer(value):
				return _invalid("Farm cells are invalid.")
		var x := int(cell[0])
		var y := int(cell[1])
		var id := int(cell[2])
		if x < 0 or y < 0 or x >= int(grid.width) or y >= int(grid.height) or id < 0 or id >= KINDS.size():
			return _invalid("Farm cells are outside the grid.")
		var coordinate := Vector2i(x, y)
		if seen.has(coordinate) or not palette.has(KINDS[id]):
			return _invalid("Farm cells or surfaces are inconsistent.")
		seen[coordinate] = true
		cells.append({"x": x, "y": y, "kind": KINDS[id]})
		match id:
			8: counts.house += 1
			5: counts.water += 1
			6: counts.path += 1
			_: counts.yard += 1
	return {"ok": true, "schema": int(schema), "block_id": data.block_id, "name": data.name,
		"address": str(data.get("address", "")) if data.get("address") != null else "", "counts": counts,
		"dataset_version": data.dataset_version, "area_m2": float(data.source_area_m2) if int(schema) == 2 else float(data.inset_area_m2),
		"source_area_m2": float(data.source_area_m2), "cells": cells, "palette": palette}

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))

static func _invalid(message: String) -> Dictionary:
	return {"ok": false, "error": message}
