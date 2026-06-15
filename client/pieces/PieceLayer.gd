class_name PieceLayer
extends Node2D

## Owns all pieces and arbitrates direct manipulation: place, select, drag,
## rotate, stack, label, remove. Left mouse only (camera uses right/middle).
## Holds no rules — this is a sandbox (ADR-0005, Phase 1).

signal selection_changed(piece)            # piece or null
signal request_label_edit(piece)           # HUD opens an inline editor
signal pieces_changed()                     # something to (re)save

const DRAG_THRESHOLD := 6.0                  # px before a click becomes a drag
const ROTATE_STEP := deg_to_rad(15.0)
const ROTATE_FINE := deg_to_rad(3.0)
const NUDGE_M := 10.0

# Input gate — the HUD disables piece interaction while the measure tool is up.
var input_enabled := true

# Placement settings, driven by the HUD.
var place_mode := false
var place_type := "infantry"
var place_side := "blue"

# Advisory movement range (metres) shown around the selected piece; 0 = off.
var range_m := 0.0

var _pieces: Array[Piece] = []
var _selected: Piece = null
var _id_counter := 0

# Drag bookkeeping.
var _dragging := false
var _press_screen := Vector2.ZERO
var _drag_offset := Vector2.ZERO
# Cycle through overlapping pieces on repeated clicks at the same spot.
var _last_click_world := Vector2.INF
var _cycle_index := 0

func selected() -> Piece:
	return _selected

func pieces() -> Array[Piece]:
	return _pieces

# --- Public actions (also used by the HUD) ----------------------------------

func add_piece(type_id: String, side: String, world_pos: Vector2) -> Piece:
	_id_counter += 1
	var p := Piece.new()
	p.setup("p%d" % _id_counter, type_id, side)
	p.position = world_pos
	add_child(p)
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

func rotate_selected(by: float) -> void:
	if _selected == null:
		return
	_selected.rotation += by
	pieces_changed.emit()

func nudge_selected(delta_world: Vector2) -> void:
	if _selected == null:
		return
	_selected.position += delta_world
	pieces_changed.emit()
	queue_redraw()

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
	queue_redraw()

# --- Save / load ------------------------------------------------------------

func serialize() -> Array:
	var out := []
	for p in _pieces:
		out.append(p.to_dict())
	return out

func deserialize(arr: Array) -> void:
	clear_all()
	var max_id := 0
	for d in arr:
		var p := Piece.new()
		add_child(p)
		p.from_dict(d)
		_pieces.append(p)
		# Keep the id counter ahead of any "pN" we load.
		var num := str(d.get("id", "")).trim_prefix("p").to_int()
		max_id = maxi(max_id, num)
	_id_counter = max_id
	_select(null)

# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_down(get_global_mouse_position(), event.position)
		else:
			_on_left_up()
		return
	if event is InputEventMouseMotion and _dragging:
		_on_drag(get_global_mouse_position(), event.position)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)

func _on_left_down(world: Vector2, screen: Vector2) -> void:
	if place_mode:
		add_piece(place_type, place_side, world)
		get_viewport().set_input_as_handled()
		return
	var hit := _pick(world)
	if hit != null:
		_select(hit)
		_dragging = true
		_press_screen = screen
		_drag_offset = hit.position - world
		get_viewport().set_input_as_handled()
	else:
		_select(null)

func _on_drag(world: Vector2, screen: Vector2) -> void:
	if _selected == null:
		return
	if screen.distance_to(_press_screen) < DRAG_THRESHOLD:
		return
	_selected.position = world + _drag_offset
	queue_redraw()  # range ring follows the piece
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
			nudge_selected(Vector2(0, -NUDGE_M))
		KEY_DOWN:
			nudge_selected(Vector2(0, NUDGE_M))
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()

# Topmost piece under the point; repeated clicks at the same spot cycle down
# through an overlapping stack so buried pieces are reachable.
func _pick(world: Vector2) -> Piece:
	var hits: Array[Piece] = []
	for p in _pieces:
		if p.contains_point(world):
			hits.append(p)
	if hits.is_empty():
		_last_click_world = Vector2.INF
		return null
	hits.reverse()  # later children draw on top → topmost first
	if world.distance_to(_last_click_world) < 4.0 and hits.size() > 1:
		_cycle_index = (_cycle_index + 1) % hits.size()
	else:
		_cycle_index = 0
	_last_click_world = world
	return hits[_cycle_index]

func _select(p: Piece) -> void:
	if _selected == p:
		return
	if _selected != null:
		_selected.set_selected(false)
	_selected = p
	if _selected != null:
		_selected.set_selected(true)
	selection_changed.emit(_selected)
	queue_redraw()

# --- Advisory range ring (drawn under pieces, over terrain) ------------------

func _draw() -> void:
	if _selected == null or range_m <= 0.0:
		return
	var c := _selected.position
	draw_circle(c, range_m, Color(0.949, 0.808, 0.345, 0.10))
	draw_arc(c, range_m, 0, TAU, 96, Color(0.949, 0.808, 0.345, 0.7), 2.0)
