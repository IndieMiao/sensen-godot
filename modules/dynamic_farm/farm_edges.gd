extends RefCounted
## Grid +y points toward world -Z. The four corners run southwest, southeast, northeast, northwest.
const CORNERS := [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]
const NEIGHBORS := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
## Outward-only visual apron: even a concave miter moves < 0.25 grid cells (sqrt(2)*0.175).
const PAD_CELLS := 0.175

static func vertex_key(a: Vector2i, b: Vector2i) -> Vector4i:
	return Vector4i(a.x,a.y,b.x,b.y) if a < b else Vector4i(b.x,b.y,a.x,a.y)

static func normal(edge: int) -> Vector3:
	return Vector3(NEIGHBORS[edge].x,0,-NEIGHBORS[edge].y)

static func endpoint(data: Dictionary, cell: Vector2i, edge: int, other_edge: int, vertex: Vector3, pad: float) -> Vector3:
	var n: Vector2i = NEIGHBORS[edge]
	var other: Vector2i = NEIGHBORS[other_edge]
	var adjacent: bool = data.by_cell.has(cell+other)
	var diagonal: bool = data.by_cell.has(cell+n+other)
	if not adjacent and diagonal:
		# Point-touching boundaries retain their exact junction; never bridge an outside neck.
		return vertex
	if adjacent and diagonal:
		return vertex + (normal(edge)-normal(other_edge))*pad
	return vertex + normal(edge)*pad

static func convex(data: Dictionary, cell: Vector2i, edge: int) -> bool:
	var previous := (edge+3)%4
	return not data.by_cell.has(cell+NEIGHBORS[edge]) and not data.by_cell.has(cell+NEIGHBORS[previous]) and not data.by_cell.has(cell+NEIGHBORS[edge]+NEIGHBORS[previous])
