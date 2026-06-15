class_name Piece
extends Node2D

## A single wooden-block token on the board. Visual + data only; all input
## (select/drag/rotate) is arbitrated by PieceLayer so z-order and stacking stay
## consistent. Position is the block centre in world space (metres, y-down);
## rotation is the unit's facing.

const WOOD := Color(0.682, 0.553, 0.388)        # painted-wood base
const WOOD_EDGE := Color(0.392, 0.298, 0.184)
const SELECT := Color(0.949, 0.808, 0.345)      # gold selection ring
const LABEL_COLOR := FeatureStyles.INK
const LABEL_SIZE_M := 26.0

var id := ""
var type_id := "marker"
var side := "neutral"
var label := ""
var stack_count := 1

var selected := false

var _font: Font

func setup(p_id: String, p_type: String, p_side: String) -> void:
	id = p_id
	type_id = p_type if UnitCatalogue.is_type(p_type) else "marker"
	side = p_side if UnitCatalogue.is_side(p_side) else "neutral"
	z_index = 10
	_font = ThemeDB.fallback_font
	queue_redraw()

func half_size() -> Vector2:
	return UnitCatalogue.type_def(type_id)["size"] * 0.5

## Board position in metres (ADR-0004) — shared accessor with Piece3D so the HUD
## can read either view's selection uniformly.
func metres() -> Vector2:
	return Geo.to_metres(position)

func facing_degrees() -> float:
	return rad_to_deg(rotation)

## True if a world-space point lands on this block (respecting rotation).
func contains_point(world_pos: Vector2) -> bool:
	var local := to_local(world_pos)
	var h := half_size()
	return absf(local.x) <= h.x and absf(local.y) <= h.y

func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()

func set_label(text: String) -> void:
	label = text
	queue_redraw()

func cycle_side() -> void:
	var i := UnitCatalogue.SIDE_ORDER.find(side)
	side = UnitCatalogue.SIDE_ORDER[(i + 1) % UnitCatalogue.SIDE_ORDER.size()]
	queue_redraw()

func set_stack(n: int) -> void:
	stack_count = maxi(1, n)
	queue_redraw()

# --- Persistence (game state, ADR-0004) -------------------------------------

func to_dict() -> Dictionary:
	# Store position in metres (board space), not world, so saves are CRS-true.
	var m := Geo.to_metres(position)
	return {
		"id": id, "type": type_id, "side": side, "label": label,
		"x_m": m.x, "y_m": m.y, "facing_deg": rad_to_deg(rotation),
		"stack": stack_count,
	}

func from_dict(d: Dictionary) -> void:
	setup(str(d.get("id", "")), str(d.get("type", "marker")), str(d.get("side", "neutral")))
	position = Geo.to_world(Vector2(float(d.get("x_m", 0.0)), float(d.get("y_m", 0.0))))
	rotation = deg_to_rad(float(d.get("facing_deg", 0.0)))
	label = str(d.get("label", ""))
	stack_count = int(d.get("stack", 1))
	queue_redraw()

# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	var h := half_size()
	var side_col: Color = UnitCatalogue.side_def(side).color

	# Stack illusion: faint offset blocks behind the top one.
	for i in range(mini(stack_count - 1, 3), 0, -1):
		var off := Vector2(1, 1) * (i * 4.0)
		draw_rect(Rect2(-h + off, h * 2.0), WOOD.darkened(0.1), true)
		draw_rect(Rect2(-h + off, h * 2.0), WOOD_EDGE, false, 1.0)

	var rect := Rect2(-h, h * 2.0)
	draw_rect(rect, WOOD, true)                                   # wood base
	# Side-colour band across the top (painted identification stripe).
	var band := Rect2(-h, Vector2(h.x * 2.0, h.y * 0.55))
	draw_rect(band, side_col, true)
	draw_rect(rect, WOOD_EDGE, false, 2.0)                        # block edge

	# Front notch (facing indicator) at local top edge.
	var notch := PackedVector2Array([
		Vector2(-h.x * 0.18, -h.y), Vector2(h.x * 0.18, -h.y), Vector2(0, -h.y - h.y * 0.28)
	])
	draw_colored_polygon(notch, side_col)
	draw_polyline(notch + PackedVector2Array([notch[0]]), WOOD_EDGE, 1.5)

	# Symbol, centred.
	var sym: String = UnitCatalogue.type_def(type_id).symbol
	if _font != null:
		var sym_size := int(h.y * 1.1)
		var sw := _font.get_string_size(sym, HORIZONTAL_ALIGNMENT_CENTER, -1, sym_size)
		draw_string(_font, Vector2(-sw.x * 0.5, sym_size * 0.35), sym,
			HORIZONTAL_ALIGNMENT_CENTER, -1, sym_size, FeatureStyles.INK)

	# Selection ring + stack badge.
	if selected:
		draw_rect(Rect2(-h - Vector2(6, 6), h * 2.0 + Vector2(12, 12)), SELECT, false, 3.0)
	if stack_count > 1 and _font != null:
		var badge := "x%d" % stack_count
		draw_string(_font, Vector2(h.x - 4, -h.y + LABEL_SIZE_M), badge,
			HORIZONTAL_ALIGNMENT_RIGHT, -1, int(LABEL_SIZE_M), FeatureStyles.INK)

	# Label below the block.
	if not label.is_empty() and _font != null:
		var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, int(LABEL_SIZE_M))
		draw_string(_font, Vector2(-lw.x * 0.5, h.y + LABEL_SIZE_M + 4), label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(LABEL_SIZE_M), LABEL_COLOR)
