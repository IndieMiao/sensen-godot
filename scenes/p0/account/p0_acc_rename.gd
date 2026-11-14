extends UiDrawer
## ACC-RENAME (SGODOT-491; 不知火舞's account spec v1.1 §3; 644:197332): the profile's `Edit ›` opens this bottom drawer.
## Pad 16: `Edit name` (XB20), 12, the TextField — `Name` over the field, the name there now with the caret at its end
## and the keyboard up, `2–16 letters or numbers · You can change it every 7 days` under it — 16, `Save` (primary; grey
## till the name is another and could be one) and 10 under it `Cancel` (secondary). NAME's local check (P0AccName) and
## its three reasons in red; the server's no comes back through refuse(). Save says which name (save_pressed) and greys
## in its pending look till the host answers (saved / refuse / settle). The keyboard pushes the drawer up
## (KeyboardAvoider: the field and both keys stay above it).

signal save_pressed(name: String)
signal cancelled

const TITLE := "Edit name"
const HELPER := "2–16 letters or numbers · You can change it every 7 days"
const SAVE := "Save"
const CANCEL := "Cancel"
const GAP := 12
const KEYS_GAP := 4   # field → Save: 16 with the column's 12
const KEY_SEP := 10   # Save → Cancel
const _BELOW_FIELD := 136.0   # the keys under the field the keyboard must not cover: 16 + 48 + 10 + 48 + 14

var field: UiTextField
var save: UiCommandButton
var cancel: UiCommandButton
var was := ""
var _rejected := false
var _saving := false

func _init(current := "") -> void:
	super(0.0)
	name = "AccRename"
	was = current
	pad = UiTokens.SPACE_PAGE
	theme = UiKit.theme()
	body.add_theme_constant_override(&"separation", GAP)
	var title := UiKit.label(TITLE, UiTokens.STYLE_TITLE_XB20, UiTokens.COLOR_TEXT)
	title.name = "Title"
	body.add_child(title)
	field = UiTextField.new(P0AccName.FIELD, P0AccName.PLACEHOLDER, HELPER)
	field.max_graphemes = P0AccName.MAX_LETTERS
	field.text = current
	field.text_changed.connect(_on_typed)
	field.submitted.connect(func(_t: String): _on_save())
	body.add_child(field)
	var gap := Control.new()
	gap.custom_minimum_size.y = KEYS_GAP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gap)
	var keys := VBoxContainer.new()
	keys.name = "Keys"
	keys.add_theme_constant_override(&"separation", KEY_SEP)
	body.add_child(keys)
	save = UiCommandButton.new(SAVE)
	save.name = "Save"
	save.activated.connect(_on_save)
	keys.add_child(save)
	cancel = UiCommandButton.new(CANCEL, UiCommandButton.Kind.SECONDARY)
	cancel.name = "Cancel"
	cancel.activated.connect(func(): cancelled.emit())
	keys.add_child(cancel)
	_refresh()

func _ready() -> void:
	body.minimum_size_changed.connect(_fit)   # as tall as what is in it (wrapped lines only measure once laid out)
	_fit()
	super()
	KeyboardAvoider.attach(self, _BELOW_FIELD)
	field.input.grab_focus()
	field.input.caret_column = field.input.text.length()

func _fit() -> void:
	height = body.get_combined_minimum_size().y + pad * 2.0

## The name as it would go out (NAME's: half-width, the ends trimmed, one space at a time).
func entered() -> String:
	var n := P0AccName.fold(field.text).strip_edges()
	while n.contains("  "): n = n.replace("  ", " ")
	return n

func _on_typed(t: String) -> void:
	var why := P0AccName.local_reason(t)
	_rejected = why != ""
	if _rejected: field.set_error(str(P0AccName.WHY[why]))
	_refresh()

func _refresh() -> void:
	var n := entered()
	save.disabled = _saving or n == was or P0AccName.letters(n) < P0AccName.MIN_LETTERS or _rejected

func _on_save() -> void:
	if _saving: return
	var n := entered()
	if P0AccName.letters(n) < P0AccName.MIN_LETTERS:   # as NAME's grey key on one letter: what is wrong, in red
		if P0AccName.letters(n) > 0: field.set_error(str(P0AccName.WHY.length))
		return
	if _rejected or n == was: return
	_saving = true
	save.phase = CommandLifecycle.State.PENDING
	_refresh()
	save_pressed.emit(n)

## The server's no (name_rejected's reason): in red, Save back.
func refuse(reason: String) -> void:
	_rejected = true
	field.set_error(str(P0AccName.WHY.get(reason, P0AccName.WHY.blocked)))
	settle()

## The host's answer was not a name (a failure it toasts): Save back as it was.
func settle() -> void:
	_saving = false
	save.phase = CommandLifecycle.State.IDLE
	_refresh()
