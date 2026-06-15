class_name TerrainRenderer
extends Node2D

## Draws the baked board content (ADR-0004) in world space (metres → world via
## Geo). Stylisation is the client's job (FeatureStyles). Geometry is converted
## to world space once in build(); _draw only paints, and only re-runs when the
## board changes — camera pan/zoom is a canvas transform, not a redraw.

var _scenario: Scenario
var _contour_interval := 10.0
var _elev_lo := 0.0
var _elev_hi := 1.0

# Pre-converted, layered draw lists (world space). Polygon layers carry holes so
# a ring-with-clearing (an island in the sea, a glade in a wood) reads right
# instead of flooding the hole — each entry is {outer, holes:Array}.
var _fields: Array = []
var _woods: Array = []
var _waters: Array = []
var _settlements: Array = []
var _buildings: Array = []          # {ring:PackedVector2Array, strongpoint:bool}
var _roads: Array = []              # {pts:PackedVector2Array, style:Dictionary}
var _bridges: Array[PackedVector2Array] = []
var _contours: Array = []          # {pts:PackedVector2Array, color:Color, index:bool}

func build(scenario: Scenario) -> void:
	_scenario = scenario
	_contour_interval = scenario.contour_interval_m()
	var er := scenario.elevation_range_m()
	_elev_lo = er.x
	_elev_hi = er.y
	_fields.clear(); _woods.clear(); _waters.clear(); _settlements.clear()
	_buildings.clear(); _roads.clear(); _bridges.clear(); _contours.clear()

	for f in scenario.features:
		match f.category:
			"field":
				_add_polys(f, _fields)
			"wood":
				_add_polys(f, _woods)
			"water":
				_add_polys(f, _waters)
			"settlement":
				_add_polys(f, _settlements)
			"building":
				var role := str(f.props.get("building_role", ""))
				for ring in _world_rings(f):
					_buildings.append({"ring": ring, "strongpoint": role == "strongpoint"})
			"road":
				var style := FeatureStyles.road_style(str(f.props.get("road_class", "")))
				for pts in _world_rings(f):
					_roads.append({"pts": pts, "style": style})
			"bridge":
				for pts in _world_rings(f):
					_bridges.append(pts)
			"relief":
				var elev := float(f.props.get("elevation", 0.0))
				var is_index := _is_index_contour(elev)
				var col := FeatureStyles.contour_color(elev, _elev_lo, _elev_hi, is_index)
				for pts in _world_rings(f):
					_contours.append({"pts": pts, "color": col, "index": is_index})
	queue_redraw()

func _is_index_contour(elev: float) -> bool:
	if _contour_interval <= 0.0:
		return false
	var n := int(round(elev / _contour_interval))
	return n % 5 == 0

func _add_polys(f: Scenario.Feature, into: Array) -> void:
	# Holes (Scenario stores them) belong to the first/primary ring only.
	var holes := _world_rings_of(f.holes)
	var outers := _world_rings(f)
	for i in outers.size():
		into.append({"outer": outers[i], "holes": holes if i == 0 else []})

func _world_rings(f: Scenario.Feature) -> Array:
	return _world_rings_of(f.parts)

func _world_rings_of(rings: Array) -> Array:
	var out := []
	for part in rings:
		var w := PackedVector2Array()
		w.resize(part.size())
		for i in part.size():
			w[i] = Geo.to_world(part[i])
		out.append(w)
	return out

# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	if _scenario == null:
		return
	# Bottom-to-top order, like a printed staff map.
	for poly in _fields:
		_fill(poly, FeatureStyles.FIELD_FILL)
	for poly in _woods:
		_fill(poly, FeatureStyles.WOOD_FILL)
		_stroke(poly, FeatureStyles.WOOD_LINE, 1.5)
	for poly in _waters:
		_fill(poly, FeatureStyles.WATER_FILL)
		_stroke(poly, FeatureStyles.WATER_LINE, 1.5)
	for c in _contours:
		var w: float = 2.2 if c.index else 1.0
		draw_polyline(c.pts, c.color, w)
	for poly in _settlements:
		_fill(poly, FeatureStyles.SETTLEMENT_FILL)
		_stroke(poly, FeatureStyles.SETTLEMENT_LINE, 1.0)
	for r in _roads:
		_draw_road(r.pts, r.style)
	for pts in _bridges:
		draw_polyline(pts, FeatureStyles.BRIDGE, 5.0)
	for b in _buildings:
		_fill({"outer": b.ring, "holes": []}, FeatureStyles.BUILDING_FILL)
		if b.ring.size() < 2:
			continue  # a degenerate footprint has no outline to stroke
		if b.strongpoint:
			draw_polyline(_closed(b.ring), FeatureStyles.STRONGPOINT_LINE, 2.0)
		else:
			draw_polyline(_closed(b.ring), FeatureStyles.INK, 0.8)

func _draw_road(pts: PackedVector2Array, style: Dictionary) -> void:
	if pts.size() < 2:
		return
	var width: float = style.get("width", 3.0)
	if style.get("dashed", false):
		_draw_dashed(pts, style.get("color", FeatureStyles.INK), width)
		return
	if style.get("casing", false):
		draw_polyline(pts, FeatureStyles.ROAD_CASING, width + 2.0)
	draw_polyline(pts, style.get("color", FeatureStyles.INK), width)

func _draw_dashed(pts: PackedVector2Array, color: Color, width: float) -> void:
	var dash := 8.0
	var gap := 6.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.0:
			continue
		var dir := (b - a) / seg
		var t := 0.0
		while t < seg:
			var t2 := minf(t + dash, seg)
			draw_line(a + dir * t, a + dir * t2, color, width)
			t = t2 + gap

func _fill(poly: Dictionary, color: Color) -> void:
	var outer: PackedVector2Array = _open(poly.outer)
	if outer.size() < 3:
		return
	# Cut each hole into the outer ring with a hairline seam so the result is one
	# simple polygon draw_colored_polygon can triangulate with the hole excluded.
	var ring := outer
	for h in poly.get("holes", []):
		ring = _bridge_hole(ring, _open(h))
	# Validate first so degenerate/self-intersecting rings are skipped quietly
	# (their outline still draws) instead of spamming errors.
	if Geometry2D.triangulate_polygon(ring).is_empty():
		return
	draw_colored_polygon(ring, color)

func _stroke(poly: Dictionary, color: Color, width: float) -> void:
	if poly.outer.size() >= 2:
		draw_polyline(_closed(poly.outer), color, width)
	for h in poly.get("holes", []):
		if h.size() >= 2:
			draw_polyline(_closed(h), color, width)

# Splice `hole` into `ring` via the nearest pair of vertices, doubling the seam
# so the path runs out to the hole, around it, and back — the standard way to
# fold a hole into a simple polygon for triangulation. The hole is walked in the
# opposite winding to the ring so its area is subtracted, not added.
func _bridge_hole(ring: PackedVector2Array, hole: PackedVector2Array) -> PackedVector2Array:
	if hole.size() < 3:
		return ring
	if signf(_signed_area(hole)) == signf(_signed_area(ring)):
		hole.reverse()
	var bi := 0
	var bj := 0
	var best := INF
	for i in ring.size():
		for j in hole.size():
			var d := ring[i].distance_squared_to(hole[j])
			if d < best:
				best = d
				bi = i
				bj = j
	var out := PackedVector2Array()
	for k in range(bi + 1):
		out.append(ring[k])
	for k in hole.size():
		out.append(hole[(bj + k) % hole.size()])
	out.append(hole[bj])      # close the hole loop
	out.append(ring[bi])      # seam back to the outer ring
	for k in range(bi + 1, ring.size()):
		out.append(ring[k])
	return out

func _signed_area(ring: PackedVector2Array) -> float:
	var a := 0.0
	var n := ring.size()
	for i in n:
		var p := ring[i]
		var q := ring[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

# Drop a ring's repeated closing vertex (triangulation wants it open).
func _open(ring: PackedVector2Array) -> PackedVector2Array:
	if ring.size() >= 2 and ring[0] == ring[ring.size() - 1]:
		return ring.slice(0, ring.size() - 1)
	return ring

func _closed(ring: PackedVector2Array) -> PackedVector2Array:
	if ring.size() >= 2 and ring[0] != ring[ring.size() - 1]:
		var c := ring.duplicate()
		c.append(ring[0])
		return c
	return ring
