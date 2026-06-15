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

# Pre-converted, layered draw lists (world space).
var _fields: Array[PackedVector2Array] = []
var _woods: Array[PackedVector2Array] = []
var _waters: Array[PackedVector2Array] = []
var _settlements: Array[PackedVector2Array] = []
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
	for ring in _world_rings(f):
		into.append(ring)

func _world_rings(f: Scenario.Feature) -> Array:
	var out := []
	for part in f.parts:
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
	for ring in _fields:
		_fill(ring, FeatureStyles.FIELD_FILL)
	for ring in _woods:
		_fill(ring, FeatureStyles.WOOD_FILL)
		draw_polyline(_closed(ring), FeatureStyles.WOOD_LINE, 1.5)
	for ring in _waters:
		_fill(ring, FeatureStyles.WATER_FILL)
		draw_polyline(_closed(ring), FeatureStyles.WATER_LINE, 1.5)
	for c in _contours:
		var w: float = 2.2 if c.index else 1.0
		draw_polyline(c.pts, c.color, w)
	for ring in _settlements:
		_fill(ring, FeatureStyles.SETTLEMENT_FILL)
		draw_polyline(_closed(ring), FeatureStyles.SETTLEMENT_LINE, 1.0)
	for r in _roads:
		_draw_road(r.pts, r.style)
	for pts in _bridges:
		draw_polyline(pts, FeatureStyles.BRIDGE, 5.0)
	for b in _buildings:
		_fill(b.ring, FeatureStyles.BUILDING_FILL)
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

func _fill(ring: PackedVector2Array, color: Color) -> void:
	# GeoJSON rings repeat the first vertex to close; triangulation wants it open.
	var open := ring
	if open.size() >= 2 and open[0] == open[open.size() - 1]:
		open = open.slice(0, open.size() - 1)
	if open.size() < 3:
		return
	# draw_colored_polygon fills a simple (concave-ok) polygon by triangulating
	# internally. Validate first so degenerate/self-intersecting rings are
	# skipped quietly (their outline still draws) instead of spamming errors.
	if Geometry2D.triangulate_polygon(open).is_empty():
		return
	draw_colored_polygon(open, color)

func _closed(ring: PackedVector2Array) -> PackedVector2Array:
	if ring.size() >= 2 and ring[0] != ring[ring.size() - 1]:
		var c := ring.duplicate()
		c.append(ring[0])
		return c
	return ring
