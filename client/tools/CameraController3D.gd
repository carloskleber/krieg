class_name CameraController3D
extends Camera3D

## Orbit / pan / zoom camera for the 3D board (ADR-0009). It mirrors the 2D
## controller's mouse grammar where it can: left mouse stays reserved for piece
## interaction, right/middle-drag orbits the sand table, Shift+drag pans the
## focus across the ground, and the wheel zooms. The default is an angled
## bird's-eye looking north, so relief reads while the board still scans north-up.

const ZOOM_STEP := 1.12
const PITCH_MIN := deg_to_rad(12.0)
const PITCH_MAX := deg_to_rad(89.0)
const ORBIT_SPEED := 0.007
const PAN_SPEED := 0.0016         # fraction of distance per pixel

var _focus := Vector3.ZERO
var _yaw := 0.0
var _pitch := deg_to_rad(55.0)
var _distance := 3000.0
var _dist_min := 200.0
var _dist_max := 12000.0

var _orbiting := false
var _panning := false

func _ready() -> void:
	# A roomy far plane: boards are kilometres across and exaggerated relief adds
	# height, so keep the whole table inside the frustum.
	far = 60000.0
	near = 1.0
	_apply()

## Frame the board: focus its centre at the given ground height and back off far
## enough to see all of it.
func frame_board(size_m: Vector2, centre_height: float) -> void:
	_focus = Vector3(size_m.x * 0.5, centre_height, -size_m.y * 0.5)
	var span := maxf(size_m.x, size_m.y)
	_dist_max = span * 3.0
	_dist_min = maxf(span * 0.03, 50.0)
	_distance = clampf(span * 0.9, _dist_min, _dist_max)
	make_current()
	_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				var on: bool = event.pressed
				if event.shift_pressed:
					_panning = on
				else:
					_orbiting = on
				if on:
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom(1.0 / ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom(ZOOM_STEP)
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw -= event.relative.x * ORBIT_SPEED
			_pitch = clampf(_pitch - event.relative.y * ORBIT_SPEED, PITCH_MIN, PITCH_MAX)
			_apply()
			get_viewport().set_input_as_handled()
		elif _panning:
			_pan(event.relative)
			get_viewport().set_input_as_handled()

func _zoom(factor: float) -> void:
	_distance = clampf(_distance * factor, _dist_min, _dist_max)
	_apply()

func _pan(rel: Vector2) -> void:
	# Move the focus across the ground plane, scaled so panning feels constant on
	# screen regardless of zoom.
	var right := global_transform.basis.x
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	right.y = 0.0
	fwd = fwd.normalized()
	right = right.normalized()
	var k := _distance * PAN_SPEED
	_focus += (-right * rel.x + fwd * rel.y) * k
	_apply()

func _apply() -> void:
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)
	) * _distance
	global_position = _focus + offset
	look_at(_focus, Vector3.UP)
