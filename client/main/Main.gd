extends Node2D

## Entry point: loads a scenario package (ADR-0004) and assembles the sandbox —
## board, camera, pieces, measure tool, and HUD. No rules (ADR-0005, Phase 1).
##
## Scenario selection order:
##   1. `--scenario=<path>` on the command line
##   2. the bundled default (res://scenarios/waterloo/scenario.json)
##   3. an open-file dialog if neither resolves

const DEFAULT_SCENARIO := "res://scenarios/waterloo/scenario.json"

var _board: BoardView
var _camera: CameraController
var _pieces: PieceLayer
var _ruler: Ruler
var _hud: Hud

func _ready() -> void:
	var path := _resolve_scenario_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		_prompt_for_scenario()
		return
	_start(path)

func _resolve_scenario_path() -> String:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--scenario="):
			return arg.trim_prefix("--scenario=")
	if FileAccess.file_exists(DEFAULT_SCENARIO):
		return DEFAULT_SCENARIO
	return ""

func _start(path: String) -> void:
	var scenario := Scenario.load_from_file(path)
	if scenario == null:
		_fatal("Could not load scenario:\n%s\n\nSee the log for details." % path)
		return

	_board = BoardView.new()
	_board.name = "Board"
	add_child(_board)
	_board.load_scenario(scenario)

	_pieces = PieceLayer.new()
	_pieces.name = "Pieces"
	_pieces.z_index = 5
	add_child(_pieces)

	_ruler = Ruler.new()
	_ruler.name = "Ruler"
	add_child(_ruler)

	_camera = CameraController.new()
	_camera.name = "Camera"
	add_child(_camera)
	_camera.frame_rect(_board.world_bounds())

	_hud = Hud.new()
	_hud.name = "Hud"
	add_child(_hud)
	_hud.setup(_pieces, _ruler, _camera, _board, scenario)

	get_window().title = "Krieg — %s" % scenario.name()

# --- Scenario fallback dialog -----------------------------------------------

func _prompt_for_scenario() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("scenario.json", "Krieg scenario")
	dlg.title = "Open a scenario package (scenario.json)"
	dlg.canceled.connect(func(): _fatal("No scenario selected."))
	dlg.file_selected.connect(func(p):
		dlg.queue_free()
		_start(p))
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _fatal(message: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var dlg := AcceptDialog.new()
	dlg.dialog_text = message
	dlg.title = "Krieg"
	dlg.confirmed.connect(func(): get_tree().quit())
	dlg.canceled.connect(func(): get_tree().quit())
	layer.add_child(dlg)
	dlg.popup_centered()
