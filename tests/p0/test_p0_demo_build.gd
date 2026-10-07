extends GdUnitTestSuite
## P0 demo build (SGODOT-232 D2): the baked server file and where the first session lands.

func test_demo_config_takes_an_http_url_and_an_optional_key() -> void:
	assert_that(P0Session.demo_config('{"url": "https://example.test/preview/p0/v1/", "key": " k1 "}')).is_equal(
		{"url": "https://example.test/preview/p0/v1", "key": "k1"})
	assert_that(P0Session.demo_config('{"url": "ftp://nope"}')).is_equal({"url": "", "key": ""})
	assert_that(P0Session.demo_config("not json")).is_equal({})
	assert_that(P0Session.demo_config("")).is_equal({})

func test_the_first_world_is_the_homestead() -> void:
	if OS.get_environment("P0_SCENE") != "" or FileAccess.file_exists("user://p0_scene"): return
	assert_str(load("res://scenes/p0/p0_boot.gd").wanted()).is_equal("farm")
