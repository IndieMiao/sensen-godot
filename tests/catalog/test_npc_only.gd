extends GdUnitTestSuite
## NPC-only parts (SGODOT-229): the outpost NPCs wear them, no player can. They stay findable by part(id) and leave
## every player pool: parts_for_slot (outfit list, passers-by), a saved outfit (AvatarService._drop_missing_parts)
## and an online appearance (OnlineAppearance.config). With an empty list nothing changes.

const MANIFEST := "res://assets/avatar/parts_manifest.json"
const SHIPPED := "res://assets/avatar/npc_only.json"
const TMP := "user://test_npc_only.json"

func after_test() -> void:
	DirAccess.remove_absolute(TMP)

func _catalog() -> PartCatalog:
	return PartCatalog.load_from_file(MANIFEST)

func _ids(pool: Array) -> Array:
	return pool.map(func(m): return m.id)

func test_an_empty_list_changes_nothing() -> void:
	var plain := _catalog()
	var listed := _catalog()
	assert_int(listed.apply_npc_only(PackedStringArray())).is_equal(0)
	for slot in [&"body", &"hairHat", &"cloth", &"shoes", &"messengerBag"]:
		assert_array(_ids(listed.parts_for_slot(slot))).override_failure_message(str(slot)).is_equal(_ids(plain.parts_for_slot(slot)))
		assert_array(_ids(listed.parts_for_slot(slot, true))).is_equal(_ids(plain.parts_for_slot(slot)))
	for id in plain.all_ids():
		assert_bool(listed.is_npc_only(str(id))).is_false()

func test_an_npc_only_part_leaves_the_pools_but_stays_findable() -> void:
	var cat := _catalog()
	var pool := cat.parts_for_slot(&"hairHat")   # the catalogue's own array, as the outfit list holds it
	var before := pool.size()
	assert_int(cat.apply_npc_only(PackedStringArray(["hairhat51", "no_such_part"]))).is_equal(1)
	assert_int(pool.size()).is_equal(before - 1)
	assert_array(_ids(cat.parts_for_slot(&"hairHat"))).not_contains(["hairhat51"])
	assert_array(_ids(cat.parts_for_slot(&"hairHat", true))).contains(["hairhat51"])
	assert_object(cat.part("hairhat51")).is_not_null()
	assert_bool(cat.has_part("hairhat51")).is_true()
	assert_bool(cat.is_npc_only("hairhat51")).is_true()
	assert_int(cat.apply_npc_only(PackedStringArray(["hairhat51"]))).is_equal(0)   # already
	assert_bool(cat.set_npc_only("hairhat51", false)).is_true()
	assert_array(_ids(cat.parts_for_slot(&"hairHat"))).is_equal(_ids(_catalog().parts_for_slot(&"hairHat")))   # back in its place

func test_a_saved_outfit_drops_npc_only_parts() -> void:
	var svc: Node = auto_free(load("res://modules/avatar/avatar_service.gd").new())
	svc.catalog = _catalog()
	svc.catalog.apply_npc_only(PackedStringArray(["hairhat51"]))
	var cfg: AvatarConfig = svc.slot_table.default_config()
	cfg.slots[&"hairHat"] = "hairhat51"
	cfg.slots[&"cloth"] = "cloth11"
	svc._drop_missing_parts(cfg)
	assert_str(String(cfg.slots[&"hairHat"])).is_equal(String(svc.slot_table.default_config().slots[&"hairHat"]))
	assert_str(String(cfg.slots[&"cloth"])).is_equal("cloth11")   # an ordinary part stays

func test_online_appearance_refuses_npc_only_parts_unless_for_an_npc() -> void:
	assert_bool(Avatar.catalog.set_npc_only("hairhat51", true)).is_true()
	var raw := {"version": 1, "slots": {"hairHat": "hairhat51", "cloth": "cloth11"}}
	var wire := OnlineAppearance.config(raw)
	var npc := OnlineAppearance.config(raw, true)
	Avatar.catalog.set_npc_only("hairhat51", false)
	assert_str(String(wire.slots[&"hairHat"])).is_equal(String(Avatar.slot_table.default_config().slots[&"hairHat"]))
	assert_str(String(wire.slots[&"cloth"])).is_equal("cloth11")
	assert_str(String(npc.slots[&"hairHat"])).is_equal("hairhat51")

func test_load_npc_only_parses_and_rejects_bad_files() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string('{"version": 1, "npc_only": ["a", "b"]}')
	f.close()
	assert_array(Array(PartCatalog.load_npc_only(TMP))).is_equal(["a", "b"])
	f = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string('{"version": 2, "npc_only": ["a"]}')
	f.close()
	assert_int(PartCatalog.load_npc_only(TMP).size()).is_equal(0)
	assert_int(PartCatalog.load_npc_only("user://not_here.json").size()).is_equal(0)

func test_the_shipped_list_is_valid() -> void:
	# load_npc_only returns [] both for an empty list and a broken file: parse it independently as well.
	assert_bool(FileAccess.file_exists(SHIPPED)).is_true()
	var data = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED))
	assert_int(typeof(data)).is_equal(TYPE_DICTIONARY)
	assert_int(int(data.get("version", -1))).is_equal(PartCatalog.NPC_ONLY_VERSION)
	assert_int(typeof(data.get("npc_only"))).is_equal(TYPE_ARRAY)
	assert_int(PartCatalog.load_npc_only(SHIPPED).size()).is_equal((data.npc_only as Array).size())
	for id in data.npc_only: assert_bool(_catalog().has_part(str(id))).override_failure_message(str(id) + " is not in the manifest").is_true()
