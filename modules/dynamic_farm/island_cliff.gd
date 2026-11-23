extends RefCounted
## Render-only faces under the final guard-approved exterior lip. No new footprint,
## collision shape or draw batch. Holes and point contacts are not bridged.
const LOWEST_Y := -2.25
const WARM := Color("dba86f")
const SHADE := Color("a8805e")
const BASE := Color("806454")

static func _column(anchor: Vector3, lip: Vector3, phase: float) -> PackedVector3Array:
	# Adjacent spans (including the corner fans) evaluate the same shared endpoint.
	var grain := 0.5 + 0.32 * sin(anchor.x * 2.1 + anchor.z * 1.3 + phase) + 0.18 * cos(anchor.z * 3.7 - anchor.x * 1.4)
	var knee := anchor.lerp(lip, 0.87)
	var toe := anchor.lerp(lip, 0.18)
	knee.y = -0.84 - 0.32 * grain
	toe.y = lerpf(-1.55, LOWEST_Y, grain)
	return PackedVector3Array([lip, knee, toe])

static func append(tool: SurfaceTool, pa: Array[Vector3], pb: Array[Vector3], outward: Vector3, phase: float) -> void:
	var a := _column(pa[0], pa[-1], phase)
	var b := _column(pb[0], pb[-1], phase)
	var mid := (a[0] + b[0]) * 0.5
	var tint := 0.34 + 0.20 * sin(mid.x * 4.5 + mid.z * 2.8 + phase) + 0.12 * sin(mid.z * 6.3 - mid.x)
	var face := WARM.lerp(SHADE, tint)
	var foot := face.lerp(BASE, 0.73)
	_facet(tool, a[0], b[0], b[1], outward, face, face, face.darkened(0.06))
	_facet(tool, a[0], b[1], a[1], outward, face, face.darkened(0.06), face)
	_facet(tool, a[1], b[1], a[2], outward, face, face.darkened(0.06), foot)
	_facet(tool, b[1], b[2], a[2], outward, face.darkened(0.06), foot, foot)

static func _facet(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var cross := (b-a).cross(c-a)
	if cross.length_squared() < 0.000000000001: return
	var flip := cross.dot(outward) > 0.0
	var normal := cross.normalized() if flip else -cross.normalized()
	tool.set_normal(normal)
	tool.set_color(ca)
	tool.add_vertex(a)
	tool.set_color(cc if flip else cb)
	tool.add_vertex(c if flip else b)
	tool.set_color(cb if flip else cc)
	tool.add_vertex(b if flip else c)
