class_name ScaleBar
extends Control

## A staff-map scale bar. Picks a round number of metres whose on-screen length
## is comfortable at the current zoom, and annotates it with the 1:8000 play
## scale (ADR-0007, PLAN §7). Lives in screen space, reading the camera zoom.

const NICE_M := [10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000, 10000]
const MIN_PX := 80.0
const MAX_PX := 240.0
const PLAY_SCALE := 8000.0

var camera: Camera2D
var _font: Font
var _last_zoom := -1.0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(280, 54)

func _process(_dt: float) -> void:
	if camera == null:
		return
	if not is_equal_approx(camera.zoom.x, _last_zoom):
		_last_zoom = camera.zoom.x
		queue_redraw()

func _draw() -> void:
	if camera == null:
		return
	var px_per_m := camera.zoom.x  # 1 metre = this many screen px
	if px_per_m <= 0.0:
		return
	var metres := _pick_length(px_per_m)
	var bar_px := metres * px_per_m
	var y := size.y - 16.0
	var x0 := 8.0
	var x1 := x0 + bar_px
	var ink := FeatureStyles.INK
	# Bar with end caps.
	draw_line(Vector2(x0, y), Vector2(x1, y), ink, 2.0)
	draw_line(Vector2(x0, y - 6), Vector2(x0, y + 2), ink, 2.0)
	draw_line(Vector2(x1, y - 6), Vector2(x1, y + 2), ink, 2.0)
	# Mid tick.
	draw_line(Vector2((x0 + x1) * 0.5, y - 4), Vector2((x0 + x1) * 0.5, y + 1), ink, 1.0)
	if _font != null:
		var label := "%s m" % _fmt(metres)
		draw_string(_font, Vector2(x0, y - 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
		var paper := "1:8000  ·  %.1f cm on map" % (metres / PLAY_SCALE * 100.0)
		draw_string(_font, Vector2(x0, y + 18), paper, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FeatureStyles.INK_FAINT)

func _pick_length(px_per_m: float) -> float:
	for m in NICE_M:
		var px: float = m * px_per_m
		if px >= MIN_PX and px <= MAX_PX:
			return float(m)
	# Outside the table's range: fall back to the closest end.
	if NICE_M[0] * px_per_m > MAX_PX:
		return float(NICE_M[0])
	return float(NICE_M[-1])

func _fmt(m: float) -> String:
	if m >= 1000.0:
		return "%.0fk" % (m / 1000.0) if fmod(m, 1000.0) == 0.0 else "%.1fk" % (m / 1000.0)
	return "%.0f" % m
