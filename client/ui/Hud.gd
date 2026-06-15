class_name Hud
extends CanvasLayer

## Screen-space UI: toolbar (tool/unit/side/range/rules/file actions), a help &
## info panel, the scale bar, a measurement/LOS readout, and source attribution.
## Owns no game logic — it drives PieceLayer / Ruler / Camera / RulesEngine and
## reads the Scenario.

enum Tool { SELECT, PLACE, MEASURE, LOS }

const HELP := "LMB place/select · drag move · RMB/MMB pan · wheel zoom\nQ/E rotate (Shift=fine) · +/- stack · F side · L label · Del remove · arrows nudge\nMeasure / LOS: left-drag across the board"

var _piece_layer: PieceLayer
var _ruler: Ruler
var _camera: CameraController
var _board: BoardView
var _scenario: Scenario
var _rules: RulesEngine
var _overlay: RulesOverlay

var _tool := Tool.SELECT
var _type_opt: OptionButton
var _side_opt: OptionButton
var _rules_opt: OptionButton
var _info: RichTextLabel
var _measure_label: Label
var _scale_bar: ScaleBar
var _label_edit_panel: PanelContainer
var _label_line: LineEdit
var _editing: Piece
var _save_dialog: FileDialog
var _load_dialog: FileDialog

func setup(piece_layer: PieceLayer, ruler: Ruler, camera: CameraController, board: BoardView, scenario: Scenario, rules: RulesEngine, overlay: RulesOverlay) -> void:
	_piece_layer = piece_layer
	_ruler = ruler
	_camera = camera
	_board = board
	_scenario = scenario
	_rules = rules
	_overlay = overlay
	_build()
	_apply_tool(Tool.SELECT)
	_piece_layer.selection_changed.connect(_on_selection_changed)
	_piece_layer.request_label_edit.connect(_open_label_editor)
	_piece_layer.pieces_changed.connect(_refresh_reach)
	_ruler.measured.connect(_on_measured)
	_overlay.los_reported.connect(func(text): _measure_label.text = text)
	_on_selection_changed(null)

# --- UI construction --------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_topbar(root)
	_build_info(root)
	_build_corner(root)
	_build_label_editor(root)
	_build_dialogs(root)

func _build_topbar(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(panel)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	panel.add_child(bar)

	var group := ButtonGroup.new()
	bar.add_child(_tool_button("Select", Tool.SELECT, group, true))
	bar.add_child(_tool_button("Place", Tool.PLACE, group, false))
	bar.add_child(_tool_button("Measure", Tool.MEASURE, group, false))
	bar.add_child(_tool_button("LOS", Tool.LOS, group, false))
	bar.add_child(VSeparator.new())

	bar.add_child(_mklabel("Unit"))
	_type_opt = OptionButton.new()
	for t in UnitCatalogue.TYPE_ORDER:
		_type_opt.add_item(UnitCatalogue.type_def(t).label)
	_type_opt.item_selected.connect(_on_type_selected)
	bar.add_child(_type_opt)

	_side_opt = OptionButton.new()
	for s in UnitCatalogue.SIDE_ORDER:
		_side_opt.add_item(UnitCatalogue.side_def(s).label)
	_side_opt.item_selected.connect(_on_side_selected)
	bar.add_child(_side_opt)
	bar.add_child(VSeparator.new())

	bar.add_child(_mklabel("Range m"))
	var range_spin := SpinBox.new()
	range_spin.min_value = 0
	range_spin.max_value = 5000
	range_spin.step = 50
	range_spin.value = 0
	range_spin.value_changed.connect(func(v): _piece_layer.set_range(v))
	bar.add_child(range_spin)
	bar.add_child(VSeparator.new())

	# Rules are opt-in per game (ADR-0005); advisory only at M4.
	bar.add_child(_mklabel("Rules"))
	_rules_opt = OptionButton.new()
	_rules_opt.add_item("None")
	_rules_opt.add_item(Strategos.new().display_name())
	_rules_opt.item_selected.connect(_on_rules_selected)
	bar.add_child(_rules_opt)
	bar.add_child(VSeparator.new())

	bar.add_child(_action_button("Frame", _on_frame))
	bar.add_child(_action_button("Save", func(): _save_dialog.popup_centered_ratio(0.6)))
	bar.add_child(_action_button("Load", func(): _load_dialog.popup_centered_ratio(0.6)))
	bar.add_child(_action_button("Clear", _on_clear))

func _build_info(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(8, -8)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.custom_minimum_size = Vector2(460, 0)
	_info.scroll_active = false
	panel.add_child(_info)

func _build_corner(root: Control) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.position = Vector2(-296, -8)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(box)

	_measure_label = Label.new()
	_measure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_measure_label)

	_scale_bar = ScaleBar.new()
	_scale_bar.camera = _camera
	box.add_child(_scale_bar)

	var attrib := Label.new()
	attrib.text = _scenario.attribution_line()
	attrib.add_theme_font_size_override("font_size", 11)
	attrib.modulate = Color(1, 1, 1, 0.6)
	attrib.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(attrib)

func _build_label_editor(root: Control) -> void:
	_label_edit_panel = PanelContainer.new()
	_label_edit_panel.set_anchors_preset(Control.PRESET_CENTER)
	_label_edit_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label_edit_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_label_edit_panel.visible = false
	root.add_child(_label_edit_panel)
	var vb := VBoxContainer.new()
	_label_edit_panel.add_child(vb)
	vb.add_child(_mklabel("Piece label"))
	_label_line = LineEdit.new()
	_label_line.custom_minimum_size = Vector2(240, 0)
	_label_line.text_submitted.connect(func(_t): _confirm_label())
	vb.add_child(_label_line)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	hb.add_child(_action_button("OK", _confirm_label))
	hb.add_child(_action_button("Cancel", func(): _label_edit_panel.visible = false))

func _build_dialogs(root: Control) -> void:
	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.add_filter("*.krieg.json", "Krieg save")
	_save_dialog.current_file = "%s.krieg.json" % _scenario.name()
	_save_dialog.file_selected.connect(_do_save)
	root.add_child(_save_dialog)

	_load_dialog = FileDialog.new()
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_load_dialog.add_filter("*.krieg.json", "Krieg save")
	_load_dialog.file_selected.connect(_do_load)
	root.add_child(_load_dialog)

# --- Small builders ---------------------------------------------------------

func _tool_button(text: String, tool: int, group: ButtonGroup, pressed: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = pressed
	b.pressed.connect(func(): _apply_tool(tool))
	return b

func _action_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func _mklabel(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

# --- Tool / selection handling ----------------------------------------------

func _apply_tool(tool: int) -> void:
	_tool = tool
	_piece_layer.place_mode = tool == Tool.PLACE
	# Piece manipulation yields to the measure tape and the LOS probe.
	_piece_layer.input_enabled = tool == Tool.SELECT or tool == Tool.PLACE
	_ruler.set_enabled(tool == Tool.MEASURE)
	_overlay.set_los_enabled(tool == Tool.LOS)
	if tool != Tool.MEASURE and tool != Tool.LOS:
		_measure_label.text = ""

func _on_type_selected(idx: int) -> void:
	_piece_layer.place_type = UnitCatalogue.TYPE_ORDER[idx]

func _on_side_selected(idx: int) -> void:
	_piece_layer.place_side = UnitCatalogue.SIDE_ORDER[idx]

func _on_rules_selected(idx: int) -> void:
	_rules.configure(_scenario, RulesEngine.RULESET_IDS[idx])
	_refresh_reach()
	_on_selection_changed(_piece_layer.selected())

func _on_selection_changed(p: Piece) -> void:
	_refresh_reach()
	if p == null:
		_info.text = "[b]No piece selected[/b]\n%s\n%s" % [_rules_line(), HELP]
		return
	_overlay.set_los_unit_type(p.type_id)
	var td: Dictionary = UnitCatalogue.type_def(p.type_id)
	var sd: Dictionary = UnitCatalogue.side_def(p.side)
	var m := Geo.to_metres(p.position)
	var lbl := p.label if not p.label.is_empty() else "(unlabelled)"
	_info.text = "[b]%s[/b] · %s · facing %d° · x%d\n%s\n@ (%.0f, %.0f) m\n%s\n%s" % [
		td.label, sd.label, int(round(rad_to_deg(p.rotation))) % 360, p.stack_count, lbl, m.x, m.y, _rules_line(), HELP]

## A one-line note on the active ruleset and what the selected piece can do this
## turn (advisory — ADR-0005/0007).
func _rules_line() -> String:
	if not _rules.enabled():
		return "[i]Rules: off (sandbox)[/i]"
	var rs_name := _rules.ruleset.display_name()
	var p := _piece_layer.selected()
	if p == null:
		return "[i]Rules: %s · select a piece for its move reach; LOS tool to check sight[/i]" % rs_name
	var terr := _rules.terrain.movement_terrain_at(Geo.to_metres(p.position))
	var budget := _rules.ruleset.movement_budget(p.type_id)
	return "[i]Rules: %s · on %s · ~%.0f m/turn[/i]" % [rs_name, terr, budget]

## Recompute the selected piece's advisory move reach (terrain-aware).
func _refresh_reach() -> void:
	if _overlay == null:
		return
	var p := _piece_layer.selected()
	if p != null and _rules.enabled():
		_overlay.show_reach(p.position, p.type_id)
	else:
		_overlay.clear_reach()

func _on_measured(metres: float) -> void:
	if metres <= 0.0:
		_measure_label.text = ""
	else:
		_measure_label.text = "%.0f m  (1:8000 → %.1f cm)" % [metres, metres / 8000.0 * 100.0]

func _on_frame() -> void:
	_camera.frame_rect(_board.world_bounds())

func _on_clear() -> void:
	_piece_layer.clear_all()

# --- Label editing ----------------------------------------------------------

func _open_label_editor(p: Piece) -> void:
	_editing = p
	_label_line.text = p.label
	_label_edit_panel.visible = true
	_label_line.grab_focus()
	_label_line.select_all()

func _confirm_label() -> void:
	if _editing != null:
		_editing.set_label(_label_line.text)
		_piece_layer.pieces_changed.emit()
	_label_edit_panel.visible = false

# --- Save / load ------------------------------------------------------------

func _do_save(path: String) -> void:
	if not path.ends_with(".json"):
		path += ".krieg.json"
	GameState.save(path, _scenario, _piece_layer.serialize())

func _do_load(path: String) -> void:
	var data := GameState.read(path)
	if data.is_empty():
		return
	if not GameState.matches_scenario(data, _scenario):
		push_warning("Save '%s' was made for a different scenario/board; loading anyway." % path)
	_piece_layer.deserialize(data.get("pieces", []))
	_on_selection_changed(null)
