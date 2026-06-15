class_name Ruler
extends Node2D

## Advisory measuring tape. When enabled, left-drag draws a line; reports the
## ground distance in metres and the equivalent length on a 1:8000 staff map
## (PLAN §7: 1:8000 is the play scale). Purely a tool — measures nothing about
## rules.

signal measured(metres: float)

const PLAY_SCALE := 8000.0          # 1:8000 play scale (ADR-0007, PLAN §7)
const LINE_COLOR := Color(0.231, 0.184, 0.122, 0.9)

var enabled := false
var _font: Font
var _a := Vector2.ZERO
var _b := Vector2.ZERO
var _active := false

func _ready() -> void:
	_font = ThemeDB.fallback_font
	z_index = 20

func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		_active = false
		queue_redraw()

func clear() -> void:
	_active = false
	measured.emit(0.0)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_a = get_global_mouse_position()
			_b = _a
			_active = true
			queue_redraw()
			get_viewport().set_input_as_handled()
		else:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _active:
		_b = get_global_mouse_position()
		measured.emit(Geo.world_distance_m(_a, _b))
		queue_redraw()
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not _active:
		return
	draw_line(_a, _b, LINE_COLOR, 2.0)
	_tick(_a)
	_tick(_b)
	var metres := Geo.world_distance_m(_a, _b)
	if _font != null:
		var paper_cm := metres / PLAY_SCALE * 100.0
		var txt := "%.0f m   (1:8000 → %.1f cm)" % [metres, paper_cm]
		var mid := (_a + _b) * 0.5
		draw_string(_font, mid + Vector2(8, -8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, LINE_COLOR)

func _tick(p: Vector2) -> void:
	var perp := (_b - _a).orthogonal().normalized() * 8.0
	if perp == Vector2.ZERO:
		perp = Vector2(0, 8)
	draw_line(p - perp, p + perp, LINE_COLOR, 2.0)
