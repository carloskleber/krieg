extends Node2D

## Entry point: loads a scenario package (ADR-0004) and assembles the sandbox —
## board, camera, pieces, measure tool, advisory rules overlay, and HUD. Rules
## are opt-in and advisory only (ADR-0005, Phase 2 / M4); default is off.
##
## Scenario selection order:
##   1. `--scenario=<path>` on the command line
##   2. if exactly one package sits in res://scenarios/, load it
##   3. if several do, a startup picker (the bundled default preselected)
##   4. an open-file dialog if none are discovered

const SCENARIOS_DIR := "res://scenarios"
const DEFAULT_SCENARIO := "res://scenarios/waterloo/scenario.json"

var _board: BoardView
var _camera: CameraController
var _pieces: PieceLayer
var _ruler: Ruler
var _rules: RulesEngine
var _overlay: RulesOverlay
var _view3d: View3D
var _views: ViewManager
var _hud: Hud

func _ready() -> void:
	# 1. explicit --scenario= wins outright.
	var explicit := _cmdline_scenario()
	if not explicit.is_empty():
		if FileAccess.file_exists(explicit):
			_start(explicit)
		else:
			_fatal("Scenario not found:\n%s" % explicit)
		return

	# 2-4. discover packages in res://scenarios/ and decide.
	var found := _discover_scenarios()
	if found.is_empty():
		_prompt_for_scenario()
	elif found.size() == 1:
		_start(found[0]["path"])
	else:
		_show_picker(found)

func _cmdline_scenario() -> String:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--scenario="):
			return arg.trim_prefix("--scenario=")
	return ""

## Scan res://scenarios/ for subdirectories holding a scenario.json, returning
## ``{dir, path, name}`` dicts sorted by display name (default-first on ties).
func _discover_scenarios() -> Array:
	var out: Array = []
	var dir := DirAccess.open(SCENARIOS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var path := "%s/%s/scenario.json" % [SCENARIOS_DIR, entry]
			if FileAccess.file_exists(path):
				out.append({"dir": entry, "path": path, "name": _peek_name(path, entry)})
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
	return out

## Cheap metadata-name read for the picker (full parse happens on load).
func _peek_name(path: String, fallback: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) == TYPE_DICTIONARY:
		var meta: Dictionary = data.get("metadata", {})
		return str(meta.get("name", fallback))
	return fallback

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

	# Rules are off by default; the HUD turns a ruleset on per game (ADR-0005).
	_rules = RulesEngine.new()
	_rules.configure(scenario, "none")
	_overlay = RulesOverlay.new()
	_overlay.name = "RulesOverlay"
	_overlay.engine = _rules
	add_child(_overlay)

	_camera = CameraController.new()
	_camera.name = "Camera"
	add_child(_camera)
	_camera.frame_rect(_board.world_bounds())

	# Optional 3D board (ADR-0009), built hidden; the ViewManager toggles it in.
	_view3d = View3D.new()
	_view3d.name = "View3D"
	add_child(_view3d)
	await _view3d.build(scenario)

	_views = ViewManager.new()
	_views.name = "ViewManager"
	add_child(_views)
	_views.setup(_board, _pieces, _ruler, _overlay, _camera, _view3d)

	_hud = Hud.new()
	_hud.name = "Hud"
	add_child(_hud)
	_hud.setup(_views, _ruler, _camera, _board, scenario, _rules, _overlay)

	get_window().title = "Krieg — %s" % scenario.name()

# --- Scenario picker --------------------------------------------------------

func _show_picker(scenarios: Array) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var dlg := AcceptDialog.new()
	dlg.title = "Krieg — choose a scenario"
	dlg.ok_button_text = "Open"

	var list := ItemList.new()
	list.custom_minimum_size = Vector2(380, 240)
	var preselect := 0
	for i in scenarios.size():
		var sc: Dictionary = scenarios[i]
		list.add_item("%s    (%s)" % [sc["name"], sc["dir"]])
		if sc["path"] == DEFAULT_SCENARIO:
			preselect = i
	list.select(preselect)
	dlg.add_child(list)

	var open := func(idx: int):
		layer.queue_free()
		_start(scenarios[idx]["path"])
	dlg.confirmed.connect(func():
		var sel := list.get_selected_items()
		open.call(sel[0] if not sel.is_empty() else preselect))
	list.item_activated.connect(open)

	dlg.add_button("Browse…", true, "browse")
	dlg.custom_action.connect(func(action):
		if action == "browse":
			layer.queue_free()
			_prompt_for_scenario())

	layer.add_child(dlg)
	dlg.popup_centered()

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
