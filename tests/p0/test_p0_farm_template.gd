extends GdUnitTestSuite
## The homestead's starting template (SGODOT-342, 338·L2): by the home city's climate band only (user 10-26), from
## content.farm_templates; never by the farm's point on the map.

const P0FarmTemplate := preload("res://modules/p0/p0_farm_template.gd")
const FarmArt := preload("res://modules/farm/farm_art.gd")

## Every band has a row, and every row's style is one the farm art builds (else FarmProps would quietly fall back).
func test_every_band_has_a_template_the_art_builds() -> void:
	var table: Dictionary = P0Logic.content().get("farm_templates", {})
	for band in P0FarmTemplate.BANDS:
		assert_bool(table.has(band)).override_failure_message("no template for %s" % band).is_true()
		assert_bool(str(table[band].get("style", "")) in FarmArt.STYLES).is_true()

## For now every band wears the cottage the farm always had: the table changes nothing on screen.
func test_every_band_wears_the_cottage_for_now() -> void:
	for band in P0FarmTemplate.BANDS:
		assert_str(P0FarmTemplate.style({"profile": {"climate": band.capitalize()}})).is_equal("cottage")

## The band is the view's profile.climate (`Tropical`, as the server writes it), else the content's; an unknown one
## reads as temperate.
func test_the_band_comes_from_the_home_climate() -> void:
	assert_str(P0FarmTemplate.band({"profile": {"climate": "Tropical"}})).is_equal("tropical")
	assert_str(P0FarmTemplate.band({"profile": {"climate": "Cool"}})).is_equal("cool")
	assert_str(P0FarmTemplate.band({"profile": {"climate": "Martian"}})).is_equal("temperate")
	var written := str(P0Logic.content().get("profile", {}).get("climate", "")).to_lower()
	assert_str(P0FarmTemplate.band({})).is_equal(written if written in P0FarmTemplate.BANDS else "temperate")
	assert_str(P0FarmTemplate.band(null)).is_equal(P0FarmTemplate.band({}))

## The farm's point plays no part: two views in one band but farms kilometres apart get the same template.
func test_the_farm_point_plays_no_part() -> void:
	var a := {"profile": {"climate": "Temperate"}, "home": {"farm": {"lat": 37.76, "lng": -122.42}}}
	var b := {"profile": {"climate": "Temperate"}, "home": {"farm": {"lat": 37.70, "lng": -122.50}}}
	assert_dict(P0FarmTemplate.of(a)).is_equal(P0FarmTemplate.of(b))

## The farm builds with the template's style: no fixed style is left in the scene script.
func test_the_farm_reads_the_template() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_farm.gd")
	assert_bool(src.contains("P0FarmTemplate.style(")).is_true()
	assert_bool(src.contains("const STYLE")).is_false()
