class_name P0AccChoose
extends RefCounted
## ACC-CHOOSE (SGODOT-491; 不知火舞's spec v2 §3, the user 11-13: two ways, nothing deleted; 720:201627): the account the
## player just signed in with already has a farm. The confirm card (HOME-CHANGE-CONFIRM's, as Block's) over the sign-in
## page: `This Google account already has a farm` (Apple's, `This email already has a farm`: whole sentences), that
## farm's `Home Lv6 · Last played 3 days ago`, then for an old farm on this phone the neutral two lines (secondary, a
## hard break between: `This phone's farm won't be linked.` / `To keep it, use another account.`) — none for a new
## player (the guest race: there is no farm here to keep; 不知火舞 11-13); `Switch to that farm` (primary, not red) and
## `Try another account` (secondary). The scrim is Try another account too.

const Confirm := preload("res://scenes/p0/panels/p0_home_move_confirm.gd")
const TITLE := {"apple": "This Apple account already has a farm", "google": "This Google account already has a farm",
	"email": "This email already has a farm"}
const FARM := "Home Lv%d · Last played %s"
const KEEP := "This phone's farm won't be linked.\nTo keep it, use another account."
const SWITCH := "Switch to that farm"
const ANOTHER := "Try another account"

## `farm`: the conflict's {name, home_level, last_played_at (ms)}; `old_farm_here`: the neutral lines. Its move_pressed
## is Switch, its cancelled Try another account.
static func card(farm: Dictionary, provider: String, old_farm_here: bool, now_ms := -1.0) -> Control:
	var c = Confirm.new()
	c.name = "ChooseCard"
	c.theme = UiKit.theme()
	(c.card.find_child("Title", true, false) as Label).text = str(TITLE.get(provider, TITLE.google))
	var body := c.card.find_child("Body", true, false) as Label
	body.text = farm_line(farm, now_ms if now_ms >= 0.0 else Time.get_unix_time_from_system() * 1000.0)
	if old_farm_here:
		var keep := UiKit.label(KEEP, UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY)
		keep.name = "Keep"
		keep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.get_parent().add_child(keep)
		body.get_parent().move_child(keep, body.get_index() + 1)
	c.move.label = SWITCH
	c.move.sends = false
	c.cancel.label = ANOTHER
	return c

## `Home Lv6 · Last played 3 days ago`: days, `1 day ago`, or under a day the inbox's `5h ago` / `12m ago` (李白's).
static func farm_line(farm: Dictionary, now_ms: float) -> String:
	var mins := int((now_ms - float(farm.get("last_played_at", now_ms))) / 60000.0)
	var ago := "Just now" if mins < 1 else ("%dm ago" % mins if mins < 60 else ("%dh ago" % (mins / 60) if mins < 1440
		else ("1 day ago" if mins < 2880 else "%d days ago" % (mins / 1440))))
	return FARM % [int(farm.get("home_level", 1)), ago]
