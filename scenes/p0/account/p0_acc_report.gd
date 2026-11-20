extends UiDrawer
## ACC-REPORT, q(315)①; frames 644:197422/197528 and 火舞 11-15 minimum addendum.
## Display labels never go over the wire; only the five server REPORT_REASONS identifiers do.
signal submitted(reason: String)

const Names := preload("res://modules/p0/p0_names.gd")
const REASONS := {
	"offensive_name": "Offensive name or bio", "harassment": "Harassment",
	"offensive_voice": "Offensive voice chat", "cheating": "Cheating or bots", "other": "Something else"}
const TITLE := "Report %s"
const PRIVATE := "Reports are private. %s won't know it was you."
var title: Label
var privacy: Label
var close: UiCloseButton
var submit: UiCommandButton
var choices := {}
var selected := ""
var busy := false
var who := ""

class ReasonRow extends Button:
	var picked := false:
		set(v): picked = v; queue_redraw()
	func _init(label: String) -> void:
		custom_minimum_size.y = 52
		focus_mode = Control.FOCUS_NONE
		for s in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())
		var ink := UiKit.label(label, UiTokens.STYLE_ROW_TITLE_XB15, UiTokens.COLOR_TEXT)
		ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ink.offset_left = 50
		ink.offset_right = -12
		ink.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(ink)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTokens.COLOR_SURFACE_RAISED)
		var at := Vector2(26, size.y * 0.5)
		draw_circle(at, 10, UiTokens.COLOR_SURFACE)
		draw_arc(at, 10, 0, TAU, 48, UiTokens.COLOR_PRIMARY if picked else UiTokens.COLOR_BORDER, 2, true)
		if picked: draw_circle(at, 6, UiTokens.COLOR_PRIMARY)

func _init(person := "", voice_offered := false) -> void:
	super(432.0 if voice_offered else 380.0)
	name = "AccReport"
	who = person
	pad = UiTokens.SPACE_PAGE
	handle = false   # approved ACC-REPORT has the title/Close row, no handle painted above it
	theme = UiKit.theme()
	body.add_theme_constant_override(&"separation", 10)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	body.add_child(header)
	title = UiKit.label("", UiTokens.STYLE_TITLE_XB20, UiTokens.COLOR_TEXT)
	title.name = "Title"
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size.x = 0
	title.clip_text = true
	header.add_child(title)
	close = UiCloseButton.new()
	close.name = "Close"
	close.pressed.connect(func(): if not busy: close_requested.emit())
	header.add_child(close)
	var rows := VBoxContainer.new()
	rows.name = "Reasons"
	rows.add_theme_constant_override(&"separation", 0)
	body.add_child(rows)
	for id: String in REASONS:
		if id == "offensive_voice" and not voice_offered: continue
		var row := ReasonRow.new(REASONS[id])
		row.name = id
		row.pressed.connect(choose.bind(id))
		choices[id] = row
		rows.add_child(row)
	privacy = UiKit.label("", UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY)
	privacy.name = "Privacy"
	privacy.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	privacy.clip_text = true
	body.add_child(privacy)
	submit = UiCommandButton.new("Choose a reason")
	submit.name = "Submit"
	submit.activated.connect(_submit)
	body.add_child(submit)
	resized.connect(_names)
	_refresh()

func _ready() -> void:
	body.minimum_size_changed.connect(_fit)
	_fit()
	super()
	_names()
	_names.call_deferred()

func _fit() -> void:
	height = body.get_combined_minimum_size().y + pad * 2 + safe_bottom

func _names() -> void:
	if title == null: return
	var width := maxf(1, size.x - pad * 2 - 2)
	title.text = Names.title(TITLE, who, title.get_theme_font(&"font"), title.get_theme_font_size(&"font_size"), width - 52)
	privacy.text = Names.title(PRIVATE, who, privacy.get_theme_font(&"font"), privacy.get_theme_font_size(&"font_size"), width)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and title != null: _names()

func choose(id: String) -> void:
	if busy or not choices.has(id): return
	selected = id
	_refresh()

func _submit() -> void:
	if busy or not choices.has(selected): return
	set_busy(true)
	submitted.emit(selected)

func set_busy(on: bool) -> void:
	busy = on
	_refresh()

func _refresh() -> void:
	for id: String in choices:
		choices[id].picked = id == selected
		choices[id].disabled = busy
	close.disabled = busy
	submit.label = "Choose a reason" if selected == "" else "Submit report"
	submit.disabled = selected == ""
	submit.phase = CommandLifecycle.State.PENDING if busy else CommandLifecycle.State.IDLE

func action_area() -> Control: return submit

## A pending drawer must not move offscreen on a swipe even if its close signal would be swallowed.
func _begin(at: Vector2, sc: ScrollContainer) -> void:
	if not busy: super(at, sc)
