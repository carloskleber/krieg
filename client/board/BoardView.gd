class_name BoardView
extends Node2D

## Composes the read-only board in world space: an optional hillshade backdrop
## (ADR-0004 raster asset) beneath the vector TerrainRenderer. Pieces and
## overlays are added as siblings above this by Main, so they share the same
## metre-based world transform.

const Z_HILLSHADE := -10
const Z_TERRAIN := 0

var scenario: Scenario
var _hillshade: Sprite2D
var _terrain: TerrainRenderer

func load_scenario(s: Scenario) -> void:
	scenario = s
	_clear()
	_build_hillshade(s)
	_terrain = TerrainRenderer.new()
	_terrain.name = "Terrain"
	_terrain.z_index = Z_TERRAIN
	add_child(_terrain)
	_terrain.build(s)

## World-space rectangle covering the board (for camera framing).
func world_bounds() -> Rect2:
	var size := scenario.board_size_m() if scenario != null else Vector2(1000, 1000)
	# Board metres x:[0,w] y:[0,h] -> world x:[0,w] y:[-h,0].
	return Rect2(Vector2(0, -size.y), size)

func _build_hillshade(s: Scenario) -> void:
	var hs: Dictionary = _find_hillshade(s)
	if hs.is_empty():
		return
	var rel := str(hs.get("path", ""))
	if rel.is_empty():
		return
	var base_dir := s.source_path.get_base_dir()
	var abs_path := base_dir.path_join(rel)
	# Read bytes and decode so this works from a res:// pck too (Image.load only
	# reads the real filesystem, not the packed archive).
	if not FileAccess.file_exists(abs_path):
		push_warning("Hillshade not found: %s" % abs_path)
		return
	var bytes := FileAccess.get_file_as_bytes(abs_path)
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		push_warning("Could not decode hillshade: %s" % abs_path)
		return
	var tex := ImageTexture.create_from_image(img)
	var bounds: Array = hs.get("bounds_m", [0, 0, img.get_width(), img.get_height()])
	var minx: float = bounds[0]
	var miny: float = bounds[1]
	var maxx: float = bounds[2]
	var maxy: float = bounds[3]
	_hillshade = Sprite2D.new()
	_hillshade.name = "Hillshade"
	_hillshade.texture = tex
	_hillshade.centered = false
	# Image top-left = (minx, maxy) in metres = (minx, -maxy) in world.
	_hillshade.position = Geo.to_world(Vector2(minx, maxy))
	_hillshade.scale = Vector2((maxx - minx) / img.get_width(), (maxy - miny) / img.get_height())
	_hillshade.self_modulate = Color(1, 1, 1, 0.35)  # faint backdrop, not the star
	_hillshade.z_index = Z_HILLSHADE
	add_child(_hillshade)

# The pipeline emits "assets" as a top-level key in scenario.json. Scenario only
# keeps metadata+features, so re-read the file once for the asset descriptor.
func _find_hillshade(s: Scenario) -> Dictionary:
	if not FileAccess.file_exists(s.source_path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(s.source_path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var assets: Dictionary = data.get("assets", {})
	return assets.get("hillshade", {})

func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_hillshade = null
	_terrain = null
