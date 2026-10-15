class_name P0CookConfirm
extends UiDrawer
## The Rare / Legendary ingredient confirm (§7.2, q(200) ⑦; S12 2738:158774, 不知火舞 on 286): a pot or a batch that
## really uses a Rare or Legendary ingredient (a tag slot's pick included, seasonings not) asks first, over the kitchen
## drawer: `Cook with Sea Bass?` — the rarest such item, the first slot's on a tie. A batch adds one line, `Uses Sea Bass
## ×4 and Rock Salt ×4 for 3 pots · 4 servings.` (P0KitchenLogic.batch_confirm_line), and its key reads
## `Cook · 3 pots`; one pot has no line and `Cook`. `Not now` (or a tap outside, Back) goes back to the card.
## Confirming sends nothing itself: `confirmed` goes to the kitchen.

signal confirmed
signal back

var title := ""
var line := ""
var key := "Cook"
var cook_button: UiCommandButton

func _init(title_ := "", line_ := "", key_ := "Cook") -> void:
	super(0.0)
	title = title_
	line = line_
	key = key_
	pad = UiTokens.SPACE_PAGE
	body.add_theme_constant_override(&"separation", 8)
	var head := UiKit.label(title, UiTokens.STYLE_TITLE_XB20)
	head.name = "Title"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(head)
	if line != "":
		var l := UiKit.label(line, UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY)
		l.name = "Line"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(l)
	cook_button = UiCommandButton.new(key)
	cook_button.sends = true   # cook / batch_cook (§10.7.1 Offline)
	cook_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cook_button.activated.connect(func(): confirmed.emit())
	body.add_child(cook_button)
	var not_now := UiDismissButton.new("Not now")
	not_now.pressed.connect(func(): back.emit())
	body.add_child(not_now)
	close_requested.connect(func(): back.emit())
	_fit.call_deferred()
	body.minimum_size_changed.connect(_fit)

## As tall as what it says (the bottom sheet grows from the safe bottom).
func _fit() -> void:
	height = body.get_combined_minimum_size().y + pad * 2.0
