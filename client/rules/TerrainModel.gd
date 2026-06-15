class_name TerrainModel
extends RefCounted

## A queryable model of the board's *covering* terrain, distilled from a Scenario
## (ADR-0004) into the plain data the rules engine consumes — no Godot types,
## everything in scenario metres (y-up). This is exactly the "plain game-state
## data" ADR-0005 says rulesets operate on.
##
## Answers two questions the movement/LOS maths need, both at a world point:
##   • which play-terrain covers it (open/field/wood/settlement/building/water)
##   • is it on/near a road (a line, not an area — it overrides the cover)
##
## A uniform spatial hash keeps both queries roughly O(1): area polygons are
## bucketed by the cells their bounding box spans, road segments by the cells
## they pass through. With a few thousand features that beats scanning them all
## on every one of the thousands of probes a reach/LOS sweep makes.

const CELL_M := 80.0
const ROAD_TOL_M := 12.0            # how close to a road centreline still counts

# Cover precedence when polygons overlap — most tactically specific wins.
const COVER_PRIORITY := {
	"building": 5, "settlement": 4, "water": 3, "wood": 2, "field": 1,
}
# Scenario categories that act as covering areas (others are lines/relief).
const COVER_CATEGORIES := ["water", "wood", "field", "settlement", "building"]

class _Area:
	var category: String
	var outer: PackedVector2Array
	var holes: Array            # Array[PackedVector2Array]
	var bb_min: Vector2
	var bb_max: Vector2

var _areas: Array = []                  # Array[_Area]
var _area_cells := {}                   # Vector2i -> Array[int] (indices into _areas)
var _road_cells := {}                   # Vector2i -> Array[PackedVector2Array] (segments [a,b])
var _origin := Vector2.ZERO             # board SW corner in metres (usually 0,0)

static func from_scenario(scenario: Scenario) -> TerrainModel:
	var m := TerrainModel.new()
	m._build(scenario)
	return m

func _build(scenario: Scenario) -> void:
	for f in scenario.features:
		if f.category in COVER_CATEGORIES:
			_add_area(f)
		elif f.category == "road":
			_add_road(f)

func _add_area(f) -> void:
	for i in f.parts.size():
		var ring: PackedVector2Array = f.parts[i]
		if ring.size() < 3:
			continue
		var a := _Area.new()
		a.category = f.category
		a.outer = ring
		# Holes only travel with the first/primary ring (matches Scenario parsing).
		a.holes = f.holes if i == 0 else []
		a.bb_min = ring[0]
		a.bb_max = ring[0]
		for p in ring:
			a.bb_min = a.bb_min.min(p)
			a.bb_max = a.bb_max.max(p)
		var idx := _areas.size()
		_areas.append(a)
		# Bucket into every cell the bbox touches.
		var c0 := _cell(a.bb_min)
		var c1 := _cell(a.bb_max)
		for cx in range(c0.x, c1.x + 1):
			for cy in range(c0.y, c1.y + 1):
				_push(_area_cells, Vector2i(cx, cy), idx)

func _add_road(f) -> void:
	for line in f.parts:
		var pts: PackedVector2Array = line
		for i in range(pts.size() - 1):
			var seg := PackedVector2Array([pts[i], pts[i + 1]])
			# Stamp the segment into every cell its (padded) bbox spans.
			var lo := pts[i].min(pts[i + 1]) - Vector2(ROAD_TOL_M, ROAD_TOL_M)
			var hi := pts[i].max(pts[i + 1]) + Vector2(ROAD_TOL_M, ROAD_TOL_M)
			var c0 := _cell(lo)
			var c1 := _cell(hi)
			for cx in range(c0.x, c1.x + 1):
				for cy in range(c0.y, c1.y + 1):
					_push(_road_cells, Vector2i(cx, cy), seg)

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - _origin.x) / CELL_M), floori((p.y - _origin.y) / CELL_M))

static func _push(dict: Dictionary, key: Vector2i, value) -> void:
	if not dict.has(key):
		dict[key] = []
	dict[key].append(value)

# --- Queries (metres) -------------------------------------------------------

## The play-terrain a unit standing at `p` moves through: a road if within
## ROAD_TOL of one (roads override cover — a road through a wood is still a
## road), else the highest-priority covering polygon, else "open".
func movement_terrain_at(p: Vector2) -> String:
	if near_road(p):
		return "road"
	return cover_at(p)

## The covering polygon category at `p` ("open" if none) — ignores roads. Used
## by LOS, where a road crossing a wood does not clear the canopy.
func cover_at(p: Vector2) -> String:
	var best := "open"
	var best_pri := 0
	var bucket: Array = _area_cells.get(_cell(p), [])
	for idx in bucket:
		var a: _Area = _areas[idx]
		if p.x < a.bb_min.x or p.x > a.bb_max.x or p.y < a.bb_min.y or p.y > a.bb_max.y:
			continue
		var pri: int = COVER_PRIORITY.get(a.category, 0)
		if pri <= best_pri:
			continue
		if _point_in_area(p, a):
			best = a.category
			best_pri = pri
	return best

func near_road(p: Vector2, tol := ROAD_TOL_M) -> bool:
	var bucket: Array = _road_cells.get(_cell(p), [])
	var tol2 := tol * tol
	for seg in bucket:
		if _dist2_to_segment(p, seg[0], seg[1]) <= tol2:
			return true
	return false

# --- Geometry helpers -------------------------------------------------------

func _point_in_area(p: Vector2, a: _Area) -> bool:
	if not _point_in_ring(p, a.outer):
		return false
	for h in a.holes:
		if _point_in_ring(p, h):
			return false
	return true

static func _point_in_ring(p: Vector2, ring: PackedVector2Array) -> bool:
	var inside := false
	var n := ring.size()
	var j := n - 1
	for i in n:
		var pi := ring[i]
		var pj := ring[j]
		if ((pi.y > p.y) != (pj.y > p.y)) \
				and (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x):
			inside = not inside
		j = i
	return inside

static func _dist2_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)
