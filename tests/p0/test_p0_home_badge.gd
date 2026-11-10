extends GdUnitTestSuite
## The Home Badge in the yard (q(287), the user 11-04 「C63 A」; 赵云's homestead_badge.glb, 401): none at Lv1; from the
## first upgrade its tier's face — wood Lv2–4, bronze 5–9, silver 10–14, gold 15–17 — and the level's number on it,
## written as the model's review renders did.

const P0Farm := preload("res://scenes/p0/p0_farm.gd")

func test_the_tiers_by_level() -> void:
	var tiers := {}
	for lv in [1, 2, 4, 5, 9, 10, 14, 15, 17]: tiers[lv] = P0Logic.badge_tier(lv)
	assert_dict(tiers).is_equal({1: "", 2: "wood", 4: "wood", 5: "bronze", 9: "bronze", 10: "silver", 14: "silver",
		15: "gold", 17: "gold"})

func _farm() -> Node3D:
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_farm.gd\"\nfunc _ready() -> void: pass\nfunc _exit_tree() -> void: pass\nfunc _process(_d) -> void: pass\n"
	stub.reload()
	var farm: Node3D = load("res://scenes/p0/p0_farm.tscn").instantiate()
	farm.set_script(stub)
	add_child(auto_free(farm))
	var badge: Node3D = P0Farm.BADGE.instantiate()
	farm.add_child(badge)
	farm._plaque_node = badge
	farm._badge_number = P0Farm.badge_label(badge.find_child("BadgeNumber", true, false), "", P0Farm.BADGE_NUMBER_CAP)
	P0Farm.badge_label(badge.find_child("BadgeLv", true, false), "Lv", P0Farm.BADGE_LV_CAP)
	return farm

func _faces(badge: Node3D) -> Array:
	return ["wood", "bronze", "silver", "gold"].filter(func(t): return (badge.find_child("Tier_" + t, true, false) as Node3D).visible)

func test_none_at_lv1_then_the_tier_and_number_of_the_level() -> void:
	var farm := _farm()
	var badge: Node3D = farm._plaque_node
	farm._show_badge(1)
	assert_bool(badge.visible).is_false()
	farm._show_badge(3)
	assert_bool(badge.visible).is_true()
	assert_array(_faces(badge)).is_equal(["wood"])
	assert_str(farm._badge_number.text).is_equal("3")
	farm._show_badge(10)
	assert_array(_faces(badge)).is_equal(["silver"])
	assert_str(farm._badge_number.text).is_equal("10")
	farm._show_badge(17)
	assert_array(_faces(badge)).is_equal(["gold"])
	assert_str(farm._badge_number.text).is_equal("17")

## As the model's review renders wrote them (its README): Nunito ExtraBold, 0.002 m a pixel, the number's cap 0.315 m
## (font size 223) and `Lv`'s 0.08 m (57), ink #3B2F25, no outline, unshaded, one sided, never turning to the camera;
## on the sockets, so they tilt with the face; never translated.
## 周瑜 on #964: a model without its sockets (renamed later) shows no number and reads no null (iOS Release would crash).
func test_a_badge_without_its_sockets_shows_no_number() -> void:
	var farm := _farm()
	assert_object(P0Farm.badge_label(null, "Lv", P0Farm.BADGE_LV_CAP)).is_null()
	farm._badge_number = null
	farm._badge_level = -1
	farm._show_badge(5)
	assert_array(_faces(farm._plaque_node)).is_equal(["bronze"])

## 上官婉儿 401 60e493d5 / 不知火舞 b3d362ee: 1.1 times the model, its proportions kept (the number ≥ 14 px at 0.8).
func test_the_badge_is_a_tenth_larger_than_the_model() -> void:
	assert_float(P0Farm.BADGE_SCALE).is_equal_approx(1.1, 1e-6)
	assert_vector(P0Farm.BADGE_HIT).is_equal_approx(Vector3(0, 1.1, 0), Vector3.ONE * 1e-6)

func test_the_number_is_written_as_the_review_renders() -> void:
	var farm := _farm()
	var number: Label3D = farm._badge_number
	assert_object(number.get_parent()).is_same(farm._plaque_node.find_child("BadgeNumber", true, false))
	assert_int(number.font_size).is_equal(223)
	assert_float(number.pixel_size).is_equal_approx(0.002, 1e-6)
	assert_str(number.modulate.to_html(false)).is_equal("3b2f25")
	assert_bool(number.shaded or number.double_sided).is_false()
	assert_int(number.billboard).is_equal(BaseMaterial3D.BILLBOARD_DISABLED)
	assert_int(number.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	var lv := farm._plaque_node.find_child("BadgeLv", true, false).get_child(0) as Label3D
	assert_str(lv.text).is_equal("Lv")
	assert_int(lv.font_size).is_equal(57)
