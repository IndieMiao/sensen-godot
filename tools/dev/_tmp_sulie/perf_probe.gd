extends Node
## Temporary (苏烈, SGODOT-328, not committed): the map's render cost while silhouettes are on screen, averaged.
var secs := 6.0
var _t := 0.0
var _n := 0
var _cpu := 0.0
var _gpu := 0.0
var _draws := 0.0
var _prims := 0.0
var _frame := 0.0
var _map: Node

func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func _process(dt: float) -> void:
	_t += dt
	if _t < 1.0: return   # settle
	var vp := get_viewport().get_viewport_rid()
	_n += 1
	_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_frame += dt
	if _t >= 1.0 + secs:
		var sil := 0
		var pins := 0
		for p in get_tree().root.find_children("*", "UiMapDestination", true, false):
			if (p as CanvasItem).is_visible_in_tree():
				pins += 1
				if (p as UiMapDestination).silhouette: sil += 1
		print("PERF328 frames %d  frame %.3f ms  render_cpu %.3f ms  render_gpu %.3f ms  draws %.1f  prims %.0f  pins %d  silhouettes %d" % [
			_n, _frame * 1000.0 / _n, _cpu / _n, _gpu / _n, _draws / _n, _prims / _n, pins, sil])
		queue_free()
