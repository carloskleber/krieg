class_name ViewManager
extends Node

## Toggles the board between the 2D staff map and the optional 3D relief view
## (ADR-0009), keeping a single source of truth: the metres-based piece list
## (GameState, ADR-0004). On every switch it serialises the pieces from the view
## being left and rebuilds them in the one being entered, so positions, facing,
## stacking, and labels carry across; the HUD is rebound to whichever layer is
## now live. Only one view processes input / renders at a time.

enum Mode { TWO_D, THREE_D }

var mode := Mode.TWO_D

# 2D set.
var _board: BoardView
var _pieces2d: PieceLayer
var _ruler: Ruler
var _overlay: RulesOverlay
var _camera2d: CameraController

# 3D set.
var _view3d: View3D

var _hud: Hud

func setup(board: BoardView, pieces2d: PieceLayer, ruler: Ruler, overlay: RulesOverlay,
		camera2d: CameraController, view3d: View3D) -> void:
	_board = board
	_pieces2d = pieces2d
	_ruler = ruler
	_overlay = overlay
	_camera2d = camera2d
	_view3d = view3d
	_apply_mode()

func set_hud(hud: Hud) -> void:
	_hud = hud

func is_3d() -> bool:
	return mode == Mode.THREE_D

## The piece layer the HUD should currently drive (PieceLayer or Piece3DLayer —
## both share the same surface).
func active_pieces() -> Object:
	return _view3d.piece_layer if is_3d() else _pieces2d

func toggle() -> void:
	set_mode(Mode.TWO_D if is_3d() else Mode.THREE_D)

func set_mode(target: int) -> void:
	if target == mode:
		return
	# Carry the pieces from the outgoing view into the incoming one.
	var carried: Array = active_pieces().serialize()
	mode = target
	active_pieces().deserialize(carried)
	_apply_mode()
	if _hud != null:
		_hud.on_view_changed()

## Frame the whole board in whichever view is active.
func frame() -> void:
	if is_3d():
		_view3d.frame()
	else:
		_camera2d.frame_rect(_board.world_bounds())

## Vertical exaggeration only affects the 3D view.
func set_exaggeration(value: float) -> void:
	_view3d.set_exaggeration(value)

func _apply_mode() -> void:
	var three := is_3d()
	# Visibility.
	_board.visible = not three
	_pieces2d.visible = not three
	_ruler.visible = not three
	_overlay.visible = not three
	_view3d.visible = three
	# Input routing — only the active view listens.
	_pieces2d.set_process_unhandled_input(not three)
	_camera2d.set_process_unhandled_input(not three)
	_ruler.set_process_unhandled_input(not three)
	_overlay.set_process_unhandled_input(not three)
	_view3d.camera.set_process_unhandled_input(three)
	_view3d.piece_layer.set_process_unhandled_input(three)
	# Active camera.
	if three:
		_view3d.camera.make_current()
	else:
		_camera2d.make_current()
