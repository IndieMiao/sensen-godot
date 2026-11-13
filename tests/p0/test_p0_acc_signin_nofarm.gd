extends GdUnitTestSuite
## ACC-SIGNIN (636:197174 / 636:197202) and ACC-NOFARM (636:197230): the card at 190, Apple first on an iPhone, the ‹ in
## its corner; No farm found's whole sentences.

func test_sign_in_card_places_and_order() -> void:
	var s: P0AccSignIn = auto_free(P0AccSignIn.new(["apple", "google"]))
	add_child(s)
	s.size = Vector2(360, 800)
	await await_idle_frame()
	assert_float(s.card.position.y).is_equal(190.0)
	assert_vector(s.back_key.position).is_equal(Vector2(21, 195))
	var apple := s.find_child("Apple", true, false) as Control
	var google := s.find_child("Google", true, false) as Control
	assert_float(apple.global_position.y).is_less(google.global_position.y)   # Apple first (HIG)
	assert_float(apple.size.y).is_equal(50.0)
	assert_float(google.size.y).is_equal(50.0)
	assert_float(apple.size.x).is_equal(google.size.x)

func test_no_farm_says_whose_account_in_a_whole_sentence() -> void:
	for c in [["apple", "This Apple account has no farm yet."], ["google", "This Google account has no farm yet."]]:
		var n: P0AccNoFarm = auto_free(P0AccNoFarm.new(str(c[0])))
		add_child(n)
		var labels := n.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
		assert_array(labels).contains([str(c[1])])
