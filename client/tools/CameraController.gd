class_name CameraController
extends Camera2D

## Pan/zoom for the board. Left mouse is reserved for piece interaction, so
## panning is on right- or middle-drag; zoom is the wheel, anchored at the
## cursor so the point under the mouse stays put.

const ZOOM_STEP := 1.15
const ZOOM_MIN := 0.02   # zoomed far out (whole board)
const ZOOM_MAX := 8.0    # zoomed right in on a piece

var _panning := false

func _ready() -> void:
	make_current()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
				if _panning:
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_at(get_global_mouse_position(), ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_at(get_global_mouse_position(), 1.0 / ZOOM_STEP)
	elif event is InputEventMouseMotion and _panning:
		# Move the camera opposite to the drag, scaled by current zoom.
		position -= event.relative / zoom
		get_viewport().set_input_as_handled()

func _zoom_at(anchor_world: Vector2, factor: float) -> void:
	var target := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(target, zoom.x):
		return
	zoom = Vector2(target, target)
	# Shift so the world point under the cursor stays under the cursor.
	var after := get_global_mouse_position()
	position += anchor_world - after

## Frame a world-space rectangle with a little margin.
func frame_rect(rect: Rect2, margin := 1.1) -> void:
	position = rect.get_center()
	var vp := get_viewport_rect().size
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var fit := clampf(minf(vp.x / rect.size.x, vp.y / rect.size.y) / margin, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(fit, fit)
