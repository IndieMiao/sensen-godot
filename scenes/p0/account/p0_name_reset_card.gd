extends RefCounted
## q(326), approved 2026-11-18: one OK, centered confirm card; report the reset without promising a new lock period.
const Confirm := preload("res://scenes/p0/panels/p0_home_move_confirm.gd")
const TITLE := "Your name was reset"
const BODY := "It didn't follow our rules."

static func card() -> Control:
	var c = Confirm.new()
	c.name = "NameResetCard"
	c.theme = UiKit.theme()
	(c.card.find_child("Title", true, false) as Label).text = TITLE
	var old_body := c.card.find_child("Body", true, false) as Label
	var body := UiKit.label(BODY, UiTokens.STYLE_BODY_R14)
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var column := old_body.get_parent()
	var index := old_body.get_index()
	column.remove_child(old_body)
	old_body.free()
	column.add_child(body)
	column.move_child(body, index)
	c.cancel.get_parent().remove_child(c.cancel)
	c.cancel.free()
	c.cancel = null
	c.move.label = "OK"
	c.move.sends = false   # reading the notice is allowed offline; persistence is a separate asynchronous ACK
	return c
