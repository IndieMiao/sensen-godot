extends GdUnitTestSuite
## SGODOT-356: the iOS map bridge sends the city colours as Android's setCityStyle, and again with LANG's repeats, so
## one sent before MapUnderlay.swift's listener was up still lands.

class Recording extends MapBridgeIOS:
	var sent: Array = []
	func _send(s: String) -> void: sent.append(s)

func test_city_style_goes_out_and_again_with_the_repeats() -> void:
	var b := Recording.new()
	b.set_city_style(true)
	assert_array(b.sent).contains_exactly(["CITYSTYLE|1"])
	b.sent.clear()
	for i in MapBridgeIOS.CREATE_RESEND_FRAMES: b.poll()
	assert_array(b.sent).contains(["CITYSTYLE|1"])
	b.set_city_style(false)
	assert_str(b.sent.back()).is_equal("CITYSTYLE|0")
