extends GdUnitTestSuite
## extract_parts --append (SGODOT-229): new parts go into parts_manifest.json without touching the existing entries.
## The merge is pure text work, tested here without importing any FBX.

const Extract := preload("res://tools/pipeline/extract_parts.gd")
const MANIFEST := "res://assets/avatar/parts_manifest.json"

func _entry(id: String, slot := "hairHat") -> Dictionary:
	return {"attach": "socket", "id": id, "pack": "builtin", "res": "res://assets/avatar/parts/%s.res" % id, "slot": slot,
		"thumb": "res://assets/avatar/thumbs/%s.png" % id, "tier": 0, "unity_guid": "00112233445566778899aabbccddeeff",
		"offset": {"pos": [0.0, 0.0, 0.0], "rot": [0.0, 0.0, 0.0], "scale": [1.0, 1.0, 1.0]}}

func test_appending_writes_what_the_default_mode_would_write_for_the_same_entries() -> void:
	var a := _entry("hairhat0")
	var b := _entry("cloth0", "cloth")
	var c := _entry("fixture_new_mask", "mask")
	var before := JSON.stringify({"version": 1, "parts": [a, b]}, "\t")
	var full := JSON.stringify({"version": 1, "parts": [a, b, c]}, "\t")
	assert_str(Extract.append_entries(before, [c])).is_equal(full)

func test_the_shipped_manifest_stays_byte_for_byte_ahead_of_the_new_entries() -> void:
	var text := FileAccess.get_file_as_string(MANIFEST)
	var before: Array = JSON.parse_string(text).parts
	var added := [_entry("fixture_new_mask", "mask"), _entry("fixture_new_hat")]
	var out := Extract.append_entries(text, added)
	var close := text.rfind("\n\t]")
	assert_str(out.substr(0, close)).is_equal(text.substr(0, close))   # every existing entry, unchanged
	assert_str(out.substr(out.length() - (text.length() - close))).is_equal(text.substr(close))   # the same closing
	var after: Array = JSON.parse_string(out).parts
	assert_int(after.size()).is_equal(before.size() + 2)
	assert_array(after.slice(0, before.size())).is_equal(before)
	assert_array(after.slice(before.size()).map(func(p): return p.id)).is_equal(["fixture_new_mask", "fixture_new_hat"])

func test_nothing_to_add_leaves_the_text_alone_and_a_broken_text_is_refused() -> void:
	var text := FileAccess.get_file_as_string(MANIFEST)
	assert_str(Extract.append_entries(text, [])).is_equal(text)
	assert_str(Extract.append_entries("{}", [_entry("x")])).is_empty()

## A fixture manifest, not the shipped one: once the 229 parts are appended they are no longer missing there.
func test_only_ids_missing_from_the_manifest_are_extracted() -> void:
	var recipes := [{"id": "hairhat51"}, {"id": "fixture_new_mask"}, {"id": "cloth11"}, {"id": "fixture_new_cloth"}]
	var manifest_parts := [_entry("hairhat51"), _entry("cloth11", "cloth"), _entry("glass1", "glass")]
	assert_array(Extract.pending(recipes, manifest_parts).map(func(r): return r.id)).is_equal(["fixture_new_mask", "fixture_new_cloth"])
	assert_array(Extract.pending(recipes.slice(0, 1) + recipes.slice(2, 3), manifest_parts)).is_empty()

## The new entries go into "parts", even when another top-level array follows it in the sorted keys.
func test_entries_land_in_parts_not_in_a_later_top_level_array() -> void:
	var a := _entry("hairhat0")
	var c := _entry("fixture_new_mask", "mask")
	var before := JSON.stringify({"version": 1, "parts": [a], "tags": ["x"]}, "\t")
	var full := JSON.stringify({"version": 1, "parts": [a, c], "tags": ["x"]}, "\t")
	assert_str(Extract.append_entries(before, [c])).is_equal(full)
	assert_str(Extract.append_entries(JSON.stringify({"version": 1, "parts": []}, "\t"), [c])).is_empty()
