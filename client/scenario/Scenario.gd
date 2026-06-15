class_name Scenario
extends RefCounted

## Parsed, read-only representation of a scenario package (ADR-0004).
##
## The client never mutates this — it is baked board content. Mutable play state
## (piece positions) lives separately in GameState. Geometry is kept in metres
## exactly as authored; conversion to Godot world space happens at draw time via
## Geo, so this stays a faithful mirror of scenario.json.

const SUPPORTED_MAJOR := 0  # format_version "0.x"; refuse unknown majors.

class Feature:
	var category: String          # relief | water | wood | field | road | bridge | settlement | building
	var props: Dictionary         # category-specific (road_class, elevation, building_role, name, ...)
	var geom_type: String         # Point | LineString | MultiLineString | Polygon | MultiPolygon
	## Rings/lines as Array of PackedVector2Array, in metres (y up). For points,
	## a single 1-element array. Polygons keep only outer rings for now (holes
	## are rare in this data and handled by even-odd fill if present).
	var parts: Array = []
	var holes: Array = []         # parallel to parts for polygons; empty if none

var format_version := ""
var metadata := {}
var features: Array[Feature] = []
var source_path := ""

# --- Convenience metadata accessors -----------------------------------------

func name() -> String:
	return metadata.get("name", "scenario")

func board_size_m() -> Vector2:
	var b: Array = metadata.get("board_size_m", [1000.0, 1000.0])
	return Vector2(b[0], b[1])

func config_hash() -> String:
	return metadata.get("config_hash", "")

func contour_interval_m() -> float:
	return float(metadata.get("contour_interval_m", 10.0))

func elevation_range_m() -> Vector2:
	var e: Array = metadata.get("elevation_range_m", [0.0, 1.0])
	return Vector2(e[0], e[1])

func attribution_line() -> String:
	var a: Dictionary = metadata.get("attribution", {})
	var parts := []
	for k in a:
		parts.append(str(a[k]))
	return "  ".join(parts)

# --- Loading -----------------------------------------------------------------

## Load and parse a scenario.json from an absolute or res:// path.
## Returns a Scenario on success, or null (and pushes an error) on failure.
static func load_from_file(path: String) -> Scenario:
	if not FileAccess.file_exists(path):
		push_error("Scenario not found: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Scenario file is empty or unreadable: %s" % path)
		return null
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Scenario JSON is not an object: %s" % path)
		return null
	return _from_dict(data, path)

static func _from_dict(data: Dictionary, path: String) -> Scenario:
	var s := Scenario.new()
	s.source_path = path
	s.format_version = str(data.get("format_version", ""))
	var major := s.format_version.split(".")[0].to_int() if not s.format_version.is_empty() else -1
	if major != SUPPORTED_MAJOR:
		push_error("Unsupported scenario format_version '%s' (client supports %d.x)" % [s.format_version, SUPPORTED_MAJOR])
		return null
	s.metadata = data.get("metadata", {})
	for raw in data.get("features", []):
		var f := _parse_feature(raw)
		if f != null:
			s.features.append(f)
	return s

static func _parse_feature(raw: Dictionary) -> Feature:
	var geom: Dictionary = raw.get("geometry", {})
	var gtype := str(geom.get("type", ""))
	if gtype.is_empty():
		return null
	var f := Feature.new()
	f.category = str(raw.get("category", "unknown"))
	f.props = raw.get("props", {})
	f.geom_type = gtype
	var coords: Variant = geom.get("coordinates", [])
	match gtype:
		"Point":
			f.parts = [_ring([coords])]
		"LineString":
			f.parts = [_ring(coords)]
		"MultiLineString":
			for line in coords:
				f.parts.append(_ring(line))
		"Polygon":
			# coords = [outer, hole1, hole2, ...]
			if coords.size() > 0:
				f.parts = [_ring(coords[0])]
				for i in range(1, coords.size()):
					f.holes.append(_ring(coords[i]))
		"MultiPolygon":
			for poly in coords:
				if poly.size() > 0:
					f.parts.append(_ring(poly[0]))
					# Holes of secondary polygons are dropped; rare in period data.
	return f

static func _ring(coords: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(coords.size())
	for i in coords.size():
		var c: Array = coords[i]
		out[i] = Vector2(c[0], c[1])  # metres, y up
	return out
