class_name Heightfield
extends RefCounted

## Samples ground elevation (metres, no exaggeration) anywhere on the board for
## the 3D view (ADR-0009). Primary source is the scenario's `heightmap` asset: a
## DEM-derived raster whose 16-bit height is packed into the R (high byte) and G
## (low byte) channels of an RGBA8 PNG ("rg16-linear"), normalised over the
## heightmap's elevation range. Sampling is bilinear so the displaced terrain
## mesh and grounded pieces read smoothly between the coarse DEM cells.
##
## If a scenario predates the heightmap (format 0.1) we fall back to the
## contour-interpolated ElevationField already used by the rules engine — coarser
## (terraced between contours), but it keeps the 3D view working on old packages.

var _img: Image
var _bounds: Rect2          # metres: pos = (minx, miny), size = (w, h)
var _elev_lo := 0.0
var _elev_hi := 1.0
var _fallback: ElevationField
var _ok := false

## Build from a scenario. Reads the heightmap asset descriptor straight from the
## scenario.json (Scenario keeps only metadata+features, like BoardView does for
## the hillshade). Returns a usable field either way.
static func from_scenario(scenario: Scenario) -> Heightfield:
	var hf := Heightfield.new()
	if not hf._load_heightmap(scenario):
		hf._fallback = ElevationField.from_scenario(scenario)
	return hf

func has_raster() -> bool:
	return _ok

## Ground elevation in metres at board position `m` (no exaggeration applied).
func elevation_at(m: Vector2) -> float:
	if not _ok:
		return _fallback.elevation_at(m) if _fallback != null else 0.0
	# Map metres -> image space. Row 0 is the north edge (max y), so v flips.
	var u := (m.x - _bounds.position.x) / _bounds.size.x
	var v := (_bounds.position.y + _bounds.size.y - m.y) / _bounds.size.y
	var w := _img.get_width()
	var h := _img.get_height()
	var fx := clampf(u, 0.0, 1.0) * (w - 1)
	var fy := clampf(v, 0.0, 1.0) * (h - 1)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var x1 := mini(x0 + 1, w - 1)
	var y1 := mini(y0 + 1, h - 1)
	var tx := fx - x0
	var ty := fy - y0
	var top := lerpf(_decode(x0, y0), _decode(x1, y0), tx)
	var bot := lerpf(_decode(x0, y1), _decode(x1, y1), tx)
	var norm := lerpf(top, bot, ty)
	return _elev_lo + norm * (_elev_hi - _elev_lo)

# Decode the normalised height [0,1] from the RG-packed pixel at (x, y).
func _decode(x: int, y: int) -> float:
	var c := _img.get_pixel(x, y)
	var hi := roundi(c.r * 255.0)
	var lo := roundi(c.g * 255.0)
	return float(hi * 256 + lo) / 65535.0

func _load_heightmap(scenario: Scenario) -> bool:
	var desc := _find_asset(scenario)
	if desc.is_empty():
		return false
	var rel := str(desc.get("path", ""))
	var bounds: Array = desc.get("bounds_m", [])
	var er: Array = desc.get("elevation_range_m", [])
	if rel.is_empty() or bounds.size() != 4 or er.size() != 2:
		return false
	var abs_path := scenario.source_path.get_base_dir().path_join(rel)
	if not FileAccess.file_exists(abs_path):
		push_warning("Heightmap not found: %s" % abs_path)
		return false
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(abs_path)) != OK:
		push_warning("Could not decode heightmap: %s" % abs_path)
		return false
	_img = img
	_bounds = Rect2(bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1])
	_elev_lo = er[0]
	_elev_hi = er[1]
	_ok = true
	return true

func _find_asset(scenario: Scenario) -> Dictionary:
	if not FileAccess.file_exists(scenario.source_path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(scenario.source_path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var assets: Dictionary = data.get("assets", {})
	return assets.get("heightmap", {})
