class_name UiChipStack
extends Control
## ChipStack (SGODOT-351 C13, d835ac7e): a few chips of one value in the table look, each 2 higher than the one under
## it — the six on the rail's groove and the stake in the bet circle. `values` lists them bottom up (a stake mixes
## values); `state` greys the whole stack (a value the wallet cannot put down). The top chip's centre is where a chip
## lifted from it starts.

const STEP := 2.0

var values: Array = []: set = set_values
var state: UiChipToken.State = UiChipToken.State.DEFAULT: set = set_state
var _chips: Array = []

func _init(values_: Array = []) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(UiChipToken.SIZE, UiChipToken.SIZE)
	size = custom_minimum_size
	values = values_

func set_values(v: Array) -> void:
	values = v
	for c in _chips: (c as Node).free()
	_chips = []
	for i in v.size():
		var t := UiChipToken.new(int(v[i]), state)
		t.table_look = true
		t.position = Vector2([0.0, 1.0, -1.0, 0.5][i % 4], -i * STEP)   # ±1 sideways, as stacked by hand
		t.shadow = i == 0
		add_child(t)
		_chips.append(t)

func set_state(v: UiChipToken.State) -> void:
	state = v
	for c in _chips: (c as UiChipToken).state = v

## The top chip's centre, in this control.
func top_centre() -> Vector2:
	return Vector2(UiChipToken.SIZE * 0.5, UiChipToken.SIZE * 0.5 - maxi(0, values.size() - 1) * STEP)
