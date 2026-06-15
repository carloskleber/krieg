class_name RulesOverlay
extends Node2D

## Draws the M4 advisory overlays on top of the board (ADR-0005): the terrain-
## aware movement reach of the selected piece, and a line-of-sight probe. It only
## *renders* what RulesEngine computes — no rules logic lives here, and nothing
## it draws constrains piece manipulation (the overlays suggest, never enforce).
##
## Reach is recomputed when the selection or a piece changes (not every frame —
## the sweep is comparatively costly). LOS is a ruler-style drag, evaluated live.

signal los_reported(text: String)       # HUD shows the visible/blocked readout

const REACH_FILL := Color(0.376, 0.490, 0.545, 0.16)
const REACH_LINE := Color(0.298, 0.404, 0.451, 0.85)
const LOS_VISIBLE := Color(0.290, 0.471, 0.298, 0.95)   # green: clear sight
const LOS_BLOCKED := Color(0.620, 0.094, 0.094, 0.95)   # red: obstructed
const LOS_HIDDEN := Color(0.620, 0.094, 0.094, 0.30)

var engine: RulesEngine

# Reach state (world space, ready to draw).
var _reach_world := PackedVector2Array()

# LOS tool state.
var los_enabled := false
var _los_active := false
var _los_a := Vector2.ZERO              # world
var _los_b := Vector2.ZERO              # world
var _los_unit_type := "infantry"
var _los_result := {}

var _font: Font

func _ready() -> void:
	z_index = 8                          # above board/range ring, below pieces (z=10)
	_font = ThemeDB.fallback_font

# --- Reach overlay (driven by selection) ------------------------------------

func show_reach(origin_world: Vector2, unit_type: String) -> void:
	_reach_world = PackedVector2Array()
	if engine == null or not engine.enabled():
		queue_redraw()
		return
	var origin_m := Geo.to_metres(origin_world)
	var poly_m := engine.reachable_region(unit_type, origin_m)
	for p in poly_m:
		_reach_world.append(Geo.to_world(p))
	queue_redraw()

func clear_reach() -> void:
	_reach_world = PackedVector2Array()
	queue_redraw()

# --- LOS tool ---------------------------------------------------------------

func set_los_enabled(value: bool) -> void:
	los_enabled = value
	if not value:
		_los_active = false
		_los_result = {}
		los_reported.emit("")
	queue_redraw()

## The selected piece's type seeds the observer eye height; default otherwise.
func set_los_unit_type(unit_type: String) -> void:
	_los_unit_type = unit_type

func _unhandled_input(event: InputEvent) -> void:
	if not los_enabled or engine == null or not engine.enabled():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_los_a = get_global_mouse_position()
			_los_b = _los_a
			_los_active = true
			_evaluate_los()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _los_active:
		_los_b = get_global_mouse_position()
		_evaluate_los()
		get_viewport().set_input_as_handled()

func _evaluate_los() -> void:
	_los_result = engine.line_of_sight(_los_unit_type, Geo.to_metres(_los_a), Geo.to_metres(_los_b))
	var dist := Geo.world_distance_m(_los_a, _los_b)
	if _los_result.get("visible", true):
		los_reported.emit("LOS: clear over %.0f m" % dist)
	else:
		var blocked: Vector2 = Geo.to_world(_los_result.get("block_m", _los_b))
		var at := Geo.world_distance_m(_los_a, blocked)
		los_reported.emit("LOS: blocked at %.0f m (of %.0f m)" % [at, dist])
	queue_redraw()

# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	if _reach_world.size() >= 3:
		draw_colored_polygon(_reach_world, REACH_FILL)
		var loop := _reach_world
		loop.append(_reach_world[0])
		draw_polyline(loop, REACH_LINE, 2.0)
	if _los_active:
		_draw_los()

func _draw_los() -> void:
	var visible: bool = _los_result.get("visible", true)
	if visible:
		draw_line(_los_a, _los_b, LOS_VISIBLE, 2.0)
	else:
		var block: Vector2 = Geo.to_world(_los_result.get("block_m", _los_b))
		draw_line(_los_a, block, LOS_VISIBLE, 2.0)       # clear up to the obstruction
		draw_line(block, _los_b, LOS_HIDDEN, 2.0)        # dead ground beyond
		draw_circle(block, 7.0, LOS_BLOCKED)
	# Endpoints.
	draw_circle(_los_a, 5.0, LOS_VISIBLE if visible else LOS_BLOCKED)
	draw_arc(_los_b, 6.0, 0, TAU, 16, LOS_VISIBLE if visible else LOS_BLOCKED, 2.0)
