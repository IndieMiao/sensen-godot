extends Control
## A stand-in for 哪吒's P0AccFlow (scenes/p0/account/p0_acc_flow.gd) in the runtime's glue tests: its constructor, its
## signals and the calls the runtime makes on it.
signal agreed(age_ok: bool)
signal named(name: String, skip: bool)
signal sign_in(provider: String)
signal blocked()
signal failed(code: String)
var kind := ""
var refused: Array = []
func _init(k: String, _name_check: Callable, _providers: Array, _top: int) -> void: kind = k
func name_refused(r: Dictionary) -> void: refused.append(r)
func no_farm() -> void: pass
func back() -> bool: return true
