class_name ElevationField
extends RefCounted

## Samples ground elevation anywhere on the board from the scenario's contour
## lines (the "relief" features, each tagged with an `elevation` prop — ADR-0004).
## Line-of-sight needs a height at arbitrary points, but contours only give
## height *on* the lines, so we interpolate: inverse-distance weighting over the
## nearest contour vertices, found through a spatial hash so each probe stays
## cheap. Heights are in metres; queries are in scenario metres (y-up).
##
## This is intentionally coarse — enough to read ridgelines and dead ground for
## an advisory LOS overlay, not a survey-grade DEM. If a scenario carries no
## contours we degrade gracefully to a flat field at the mean elevation, so LOS
## falls back to pure terrain-occluder blocking.

const CELL_M := 70.0
const K_NEAREST := 6                # vertices blended per sample
const MAX_RING := 6                 # how far out to widen the cell search

# pos -> elevation samples, bucketed by cell.
var _cells := {}                    # Vector2i -> Array[Vector3] (x,y = pos, z = elev)
var _flat := 0.0                    # fallback elevation when no contours
var _has_data := false

static func from_scenario(scenario: Scenario) -> ElevationField:
	var f := ElevationField.new()
	f._build(scenario)
	return f

func _build(scenario: Scenario) -> void:
	var sum := 0.0
	var count := 0
	for feat in scenario.features:
		if feat.category != "relief":
			continue
		var elev := float(feat.props.get("elevation", 0.0))
		for line in feat.parts:
			for p in line:
				_push(Vector3(p.x, p.y, elev))
				sum += elev
				count += 1
	if count > 0:
		_flat = sum / count
		_has_data = true
	else:
		var er := scenario.elevation_range_m()
		_flat = (er.x + er.y) * 0.5

func _push(sample: Vector3) -> void:
	var key := _cell(Vector2(sample.x, sample.y))
	if not _cells.has(key):
		_cells[key] = []
	_cells[key].append(sample)

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL_M), floori(p.y / CELL_M))

## Interpolated ground elevation at `p` (metres). Constant when no contours.
func elevation_at(p: Vector2) -> float:
	if not _has_data:
		return _flat
	var near := _gather(p)
	if near.is_empty():
		return _flat
	# Inverse-distance weighting (1/d²); a direct hit returns that vertex's value.
	var wsum := 0.0
	var esum := 0.0
	for s in near:
		var d2: float = Vector2(s.x, s.y).distance_squared_to(p)
		if d2 < 0.01:
			return s.z
		var w := 1.0 / d2
		wsum += w
		esum += w * s.z
	return esum / wsum if wsum > 0.0 else _flat

# Collect the nearest ~K samples by widening the ring of cells around p.
func _gather(p: Vector2) -> Array:
	var c := _cell(p)
	var found := []
	for ring in range(MAX_RING + 1):
		for cx in range(c.x - ring, c.x + ring + 1):
			for cy in range(c.y - ring, c.y + ring + 1):
				# Only the freshly added outer ring each iteration.
				if ring > 0 and absi(cx - c.x) != ring and absi(cy - c.y) != ring:
					continue
				var bucket: Array = _cells.get(Vector2i(cx, cy), [])
				for s in bucket:
					found.append(s)
		if found.size() >= K_NEAREST:
			break
	return found
