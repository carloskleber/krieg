class_name Piece3DLayer
extends Node3D

## Owns the 3D pieces and arbitrates direct manipulation by raycasting from the
## camera — the 3D analogue of PieceLayer. It mirrors PieceLayer's public surface
## (signals, place settings, actions, serialize/deserialize) so the HUD can drive
## either view through one interface. Holds no rules — a sandbox (ADR-0005).

signal selection_changed(piece)
signal request_label_edit(piece)
signal pieces_changed()

const DRAG_THRESHOLD := 6.0
const ROTATE_STEP := 15.0
const ROTATE_FINE := 3.0
const NUDGE_M := 10.0
const PIECE_MASK := 1 << (Piece3D.PIECE_LAYER - 1)
const TERRAIN_MASK := 1 << (TerrainMesh3D.TERRAIN_LAYER - 1)

var input_enabled := true
var place_mode := false
var place_type := "infantry"
var place_side := "blue"
var range_m := 0.0

var _camera: Camera3D
var _terrain: TerrainMesh3D
var _heightfield: Heightfield

var _pieces: Array[Piece3D] = []
var _selected: Piece3D = null
var _id_counter := 0

var _dragging := false
var _press_screen := Vector2.ZERO
var _drag_offset := Vector2.ZERO    # metres
var _last_pick := Vector2.INF
var _cycle_index := 0
var _range_ring: MeshInstance3D

func configure(camera: Camera3D, terrain: TerrainMesh3D, heightfield: Heightfield) -> void:
	_camera = camera
	_terrain = terrain
	_heightfield = heightfield

func selected() -> Piece3D:
	return _selected

func pieces() -> Array[Piece3D]:
	return _pieces

# --- Public actions (shared with the HUD) -----------------------------------

func add_piece(type_id: String, side: String, metres: Vector2) -> Piece3D:
	_id_counter += 1
	var p := Piece3D.new()
	add_child(p)
	p.setup("p%d" % _id_counter, type_id, side)
	_ground(p, metres)
	_pieces.append(p)
	_select(p)
	pieces_changed.emit()
	return p

func remove_selected() -> void:
	if _selected == null:
		return
	_pieces.erase(_selected)
	_selected.queue_free()
	_select(null)
	pieces_changed.emit()

func clear_all() -> void:
	for p in _pieces:
		p.queue_free()
	_pieces.clear()
	_select(null)
	pieces_changed.emit()

func rotate_selected(by_deg: float) -> void:
	if _selected == null:
		return
	_selected.set_facing(_selected.facing_deg + by_deg)
	pieces_changed.emit()

func nudge_selected(delta_metres: Vector2) -> void:
	if _selected == null:
		return
	_ground(_selected, _selected.metres() + delta_metres)
	_update_range_ring()
	pieces_changed.emit()

func stack_selected(delta: int) -> void:
	if _selected == null:
		return
	_selected.set_stack(_selected.stack_count + delta)
	pieces_changed.emit()

func cycle_selected_side() -> void:
	if _selected == null:
		return
	_selected.cycle_side()
	pieces_changed.emit()

func set_range(metres: float) -> void:
	range_m = maxf(0.0, metres)
	_update_range_ring()

# --- Save / load (same schema as PieceLayer) --------------------------------

func serialize() -> Array:
	var out := []
	for p in _pieces:
		out.append(p.to_dict())
	return out

func deserialize(arr: Array) -> void:
	clear_all()
	var max_id := 0
	for d in arr:
		var p := Piece3D.new()
		add_child(p)
		p.from_dict(d)
		_ground(p, Vector2(float(d.get("x_m", 0.0)), float(d.get("y_m", 0.0))))
		_pieces.append(p)
		var num := str(d.get("id", "")).trim_prefix("p").to_int()
		max_id = maxi(max_id, num)
	_id_counter = max_id
	_select(null)

# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _camera == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_down(event.position)
		else:
			_on_left_up()
		return
	if event is InputEventMouseMotion and _dragging:
		_on_drag(event.position)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)

func _on_left_down(screen: Vector2) -> void:
	if place_mode:
		var t := _terrain_point()
		if t.hit:
			add_piece(place_type, place_side, t.metres)
			get_viewport().set_input_as_handled()
		return
	var hit := _pick_piece()
	if hit != null:
		_select(hit)
		_dragging = true
		_press_screen = screen
		_drag_offset = hit.metres() - _ray_metres_or(hit.metres())
		get_viewport().set_input_as_handled()
	else:
		_select(null)

func _on_drag(screen: Vector2) -> void:
	if _selected == null:
		return
	if screen.distance_to(_press_screen) < DRAG_THRESHOLD:
		return
	var t := _terrain_point()
	if t.hit:
		_ground(_selected, t.metres + _drag_offset)
		_update_range_ring()
		get_viewport().set_input_as_handled()

func _on_left_up() -> void:
	if _dragging:
		_dragging = false
		pieces_changed.emit()

func _on_key(event: InputEventKey) -> void:
	if _selected == null:
		return
	var handled := true
	match event.keycode:
		KEY_BRACKETLEFT, KEY_Q:
			rotate_selected(-(ROTATE_FINE if event.shift_pressed else ROTATE_STEP))
		KEY_BRACKETRIGHT, KEY_E:
			rotate_selected(ROTATE_FINE if event.shift_pressed else ROTATE_STEP)
		KEY_DELETE, KEY_X:
			remove_selected()
		KEY_F:
			cycle_selected_side()
		KEY_L:
			request_label_edit.emit(_selected)
		KEY_EQUAL, KEY_KP_ADD:
			stack_selected(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			stack_selected(-1)
		KEY_LEFT:
			nudge_selected(Vector2(-NUDGE_M, 0))
		KEY_RIGHT:
			nudge_selected(Vector2(NUDGE_M, 0))
		KEY_UP:
			nudge_selected(Vector2(0, NUDGE_M))
		KEY_DOWN:
			nudge_selected(Vector2(0, -NUDGE_M))
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()

# --- Raycasting & grounding --------------------------------------------------

func _ground(p: Piece3D, metres: Vector2) -> void:
	p.position = _terrain.surface_point(metres, _heightfield)

func _ray(mask: int) -> Dictionary:
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100000.0, mask)
	return get_world_3d().direct_space_state.intersect_ray(q)

func _terrain_point() -> Dictionary:
	var r := _ray(TERRAIN_MASK)
	if r.is_empty():
		return {"hit": false, "metres": Vector2.ZERO}
	return {"hit": true, "metres": Geo3D.to_metres(r.position)}

# Where the current ray meets the terrain, in metres; `fallback` if it misses.
func _ray_metres_or(fallback: Vector2) -> Vector2:
	var t := _terrain_point()
	return t.metres if t.hit else fallback

func _pick_piece() -> Piece3D:
	var r := _ray(PIECE_MASK)
	if r.is_empty():
		_last_pick = Vector2.INF
		return null
	var body: Object = r.collider
	if body == null or not body.has_meta("piece"):
		return null
	return body.get_meta("piece") as Piece3D

func _select(p: Piece3D) -> void:
	if _selected == p:
		return
	if _selected != null:
		_selected.set_selected(false)
	_selected = p
	if _selected != null:
		_selected.set_selected(true)
	_update_range_ring()
	selection_changed.emit(_selected)

# --- Advisory range ring -----------------------------------------------------

func _update_range_ring() -> void:
	if _selected == null or range_m <= 0.0:
		if _range_ring != null:
			_range_ring.visible = false
		return
	if _range_ring == null:
		_range_ring = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.949, 0.808, 0.345, 0.7)
		mat.emission_enabled = true
		mat.emission = Color(0.949, 0.808, 0.345)
		mat.emission_energy_multiplier = 0.4
		_range_ring.material_override = mat
		add_child(_range_ring)
	var tm := TorusMesh.new()
	tm.inner_radius = range_m - 4.0
	tm.outer_radius = range_m + 4.0
	_range_ring.mesh = tm
	_range_ring.position = _selected.position + Vector3(0, 2.0, 0)
	_range_ring.visible = true
