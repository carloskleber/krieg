class_name Hud
extends CanvasLayer

## Screen-space UI: toolbar (tool/unit/side/range/rules/view/file actions), a help
## & info panel, the scale bar, a measurement/LOS readout, and source attribution.
## Owns no game logic — it drives the *active* piece layer (2D or 3D, via the
## ViewManager, ADR-0009), the Ruler, the RulesEngine, and reads the Scenario.

enum Tool { SELECT, PLACE, MEASURE, LOS }

const HELP := "LMB place/select · drag move · RMB/MMB pan · wheel zoom\nQ/E rotate (Shift=fine) · +/- stack · F side · L label · Del remove · arrows nudge\nMeasure / LOS: left-drag across the board"
const HELP_3D := "LMB place/select · drag move · RMB/MMB orbit · Shift+drag pan · wheel zoom\nQ/E rotate · +/- stack · F side · L label · Del remove · arrows nudge"

var _view: ViewManager
var _pieces: Object             # active PieceLayer or Piece3DLayer
var _ruler: Ruler
var _camera2d: CameraController
var _board: BoardView
var _scenario: Scenario
var _rules: RulesEngine
var _overlay: RulesOverlay

var _tool := Tool.SELECT
var _place_type := "infantry"
var _place_side := "blue"
var _range := 0.0

var _select_btn: Button
var _measure_btn: Button
var _los_btn: Button
var _view_btn: Button
var _exag_slider: HSlider
var _exag_label: Label
var _type_opt: OptionButton
var _side_opt: OptionButton
var _rules_opt: OptionButton
var _info: RichTextLabel
var _hover_panel: PanelContainer
var _hover_label: Label
var _measure_label: Label
var _scale_bar: ScaleBar
var _label_edit_panel: PanelContainer
var _label_line: LineEdit
var _editing: Object
var _save_dialog: FileDialog
var _load_dialog: FileDialog

func setup(view: ViewManager, ruler: Ruler, camera2d: CameraController, board: BoardView,
		scenario: Scenario, rules: RulesEngine, overlay: RulesOverlay) -> void:
	_view = view
	_ruler = ruler
	_camera2d = camera2d
	_board = board
	_scenario = scenario
	_rules = rules
	_overlay = overlay
	_view.set_hud(self)
	_build()
	_bind_pieces()
	_apply_tool(Tool.SELECT)
	_ruler.measured.connect(_on_measured)
	_overlay.los_reported.connect(func(text): _measure_label.text = text)
	_update_view_state()
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
	_select_btn = _tool_button("Select", Tool.SELECT, group, true)
	bar.add_child(_select_btn)
	bar.add_child(_tool_button("Place", Tool.PLACE, group, false))
	_measure_btn = _tool_button("Measure", Tool.MEASURE, group, false)
	bar.add_child(_measure_btn)
	_los_btn = _tool_button("LOS", Tool.LOS, group, false)
	bar.add_child(_los_btn)
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
	range_spin.value_changed.connect(_on_range_changed)
	bar.add_child(range_spin)
	bar.add_child(VSeparator.new())

	# Rules are opt-in per game (ADR-0005); advisory only at M4, and 2D-only.
	bar.add_child(_mklabel("Rules"))
	_rules_opt = OptionButton.new()
	_rules_opt.add_item("None")
	_rules_opt.add_item(Strategos.new().display_name())
	_rules_opt.item_selected.connect(_on_rules_selected)
	bar.add_child(_rules_opt)
	bar.add_child(VSeparator.new())

	# 3D view toggle + vertical exaggeration (ADR-0009).
	_view_btn = _action_button("3D", _on_toggle_view)
	bar.add_child(_view_btn)
	_exag_label = _mklabel("×3.0")
	bar.add_child(_exag_label)
	_exag_slider = HSlider.new()
	_exag_slider.min_value = 1.0
	_exag_slider.max_value = 8.0
	_exag_slider.step = 0.5
	_exag_slider.value = View3D.DEFAULT_EXAGGERATION
	_exag_slider.custom_minimum_size = Vector2(90, 0)
	_exag_slider.value_changed.connect(_on_exag_changed)
	bar.add_child(_exag_slider)
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

	# A small caption that follows the cursor with the terrain it is over
	# (2D only; positioned each frame in _process).
	_hover_panel = PanelContainer.new()
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.visible = false
	_hover_panel.modulate = Color(1, 1, 1, 0.9)
	root.add_child(_hover_panel)
	_hover_label = Label.new()
	_hover_label.add_theme_font_size_override("font_size", 12)
	_hover_panel.add_child(_hover_label)

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
	_scale_bar.camera = _camera2d
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

# --- Active piece layer binding ---------------------------------------------

func _bind_pieces() -> void:
	_pieces = _view.active_pieces()
	_pieces.selection_changed.connect(_on_selection_changed)
	_pieces.request_label_edit.connect(_open_label_editor)
	_pieces.pieces_changed.connect(_refresh_reach)
	# Push current placement settings onto the freshly active layer.
	_pieces.place_type = _place_type
	_pieces.place_side = _place_side
	_pieces.set_range(_range)

func _unbind_pieces() -> void:
	if _pieces == null:
		return
	_pieces.selection_changed.disconnect(_on_selection_changed)
	_pieces.request_label_edit.disconnect(_open_label_editor)
	_pieces.pieces_changed.disconnect(_refresh_reach)

## Called by the ViewManager after a 2D<->3D switch.
func on_view_changed() -> void:
	_unbind_pieces()
	_bind_pieces()
	_apply_tool(_tool)
	_update_view_state()
	_on_selection_changed(_pieces.selected())

# --- Tool / selection handling ----------------------------------------------

func _apply_tool(tool: int) -> void:
	_tool = tool
	_pieces.place_mode = tool == Tool.PLACE
	# Piece manipulation yields to the measure tape and the LOS probe.
	_pieces.input_enabled = tool == Tool.SELECT or tool == Tool.PLACE
	# Ruler and LOS are 2D-only tools.
	var d3 := _view.is_3d()
	_ruler.set_enabled(not d3 and tool == Tool.MEASURE)
	_overlay.set_los_enabled(not d3 and tool == Tool.LOS)
	if tool != Tool.MEASURE and tool != Tool.LOS:
		_measure_label.text = ""

func _on_type_selected(idx: int) -> void:
	_place_type = UnitCatalogue.TYPE_ORDER[idx]
	_pieces.place_type = _place_type

func _on_side_selected(idx: int) -> void:
	_place_side = UnitCatalogue.SIDE_ORDER[idx]
	_pieces.place_side = _place_side

func _on_range_changed(v: float) -> void:
	_range = v
	_pieces.set_range(v)

func _on_rules_selected(idx: int) -> void:
	_rules.configure(_scenario, RulesEngine.RULESET_IDS[idx])
	_refresh_reach()
	_on_selection_changed(_pieces.selected())

func _on_toggle_view() -> void:
	_view.toggle()

func _on_exag_changed(v: float) -> void:
	_exag_label.text = "×%.1f" % v
	_view.set_exaggeration(v)

# Reflect the active view in the toolbar: relabel the toggle, gate 2D-only tools.
func _update_view_state() -> void:
	var d3 := _view.is_3d()
	_view_btn.text = "2D" if d3 else "3D"
	_measure_btn.disabled = d3
	_los_btn.disabled = d3
	_rules_opt.disabled = d3
	_scale_bar.visible = not d3
	if d3 and (_tool == Tool.MEASURE or _tool == Tool.LOS):
		_select_btn.button_pressed = true
		_apply_tool(Tool.SELECT)

func _on_selection_changed(p: Object) -> void:
	_refresh_reach()
	if p == null:
		var help := HELP_3D if _view.is_3d() else HELP
		_info.text = "[b]No piece selected[/b]\n%s\n%s" % [_rules_line(), help]
		return
	if not _view.is_3d():
		_overlay.set_los_unit_type(p.type_id)
	var td: Dictionary = UnitCatalogue.type_def(p.type_id)
	var sd: Dictionary = UnitCatalogue.side_def(p.side)
	var m: Vector2 = p.metres()
	var lbl: String = p.label if not p.label.is_empty() else "(unlabelled)"
	_info.text = "[b]%s[/b] · %s · facing %d° · x%d\n%s\n@ (%.0f, %.0f) m\n%s" % [
		td.label, sd.label, int(round(p.facing_degrees())) % 360, p.stack_count, lbl, m.x, m.y, _rules_line()]

## A one-line note on the active ruleset and the selected piece's reach (advisory,
## ADR-0005/0007). Rules are 2D-only; in 3D this stays a plain sandbox note.
func _rules_line() -> String:
	if _view.is_3d():
		return "[i]3D view · rules/measure are 2D-only[/i]"
	if not _rules.enabled():
		return "[i]Rules: off (sandbox)[/i]"
	var rs_name := _rules.ruleset.display_name()
	var p: Object = _pieces.selected()
	if p == null:
		return "[i]Rules: %s · select a piece for its move reach; LOS tool to check sight[/i]" % rs_name
	var terr := _rules.terrain.movement_terrain_at(p.metres())
	var budget := _rules.ruleset.movement_budget(p.type_id)
	return "[i]Rules: %s · on %s · ~%.0f m/turn[/i]" % [rs_name, terr, budget]

## Recompute the selected piece's advisory move reach (terrain-aware, 2D only).
func _refresh_reach() -> void:
	if _overlay == null:
		return
	if _view.is_3d():
		_overlay.clear_reach()
		return
	var p: Object = _pieces.selected()
	if p != null and _rules.enabled():
		_overlay.show_reach(p.position, p.type_id)
	else:
		_overlay.clear_reach()

# --- Terrain-under-cursor caption -------------------------------------------

## Each frame, show the play-terrain (and ground height) beneath the cursor in a
## caption that trails it. 2D only, and only while the pointer is over the board.
func _process(_delta: float) -> void:
	if _hover_panel == null:
		return
	if _view.is_3d() or _rules == null or _rules.terrain == null:
		_hover_panel.visible = false
		return
	var world := _board.get_global_mouse_position()
	if not _board.world_bounds().has_point(world):
		_hover_panel.visible = false
		return
	var m := Geo.to_metres(world)
	var terr: String = _rules.terrain.movement_terrain_at(m)
	var text := RulesEngine.terrain_label(terr)
	if _rules.elevation != null:
		text += " · %.0f m" % _rules.elevation.elevation_at(m)
	_hover_label.text = text
	_hover_panel.visible = true
	_hover_panel.position = get_viewport().get_mouse_position() + Vector2(18, 18)

func _on_measured(metres: float) -> void:
	if metres <= 0.0:
		_measure_label.text = ""
	else:
		_measure_label.text = "%.0f m  (1:8000 → %.1f cm)" % [metres, metres / 8000.0 * 100.0]

func _on_frame() -> void:
	_view.frame()

func _on_clear() -> void:
	_pieces.clear_all()

# --- Label editing ----------------------------------------------------------

func _open_label_editor(p: Object) -> void:
	_editing = p
	_label_line.text = p.label
	_label_edit_panel.visible = true
	_label_line.grab_focus()
	_label_line.select_all()

func _confirm_label() -> void:
	if _editing != null:
		_editing.set_label(_label_line.text)
		_pieces.pieces_changed.emit()
	_label_edit_panel.visible = false

# --- Save / load ------------------------------------------------------------

func _do_save(path: String) -> void:
	if not path.ends_with(".json"):
		path += ".krieg.json"
	GameState.save(path, _scenario, _pieces.serialize())

func _do_load(path: String) -> void:
	var data := GameState.read(path)
	if data.is_empty():
		return
	if not GameState.matches_scenario(data, _scenario):
		push_warning("Save '%s' was made for a different scenario/board; loading anyway." % path)
	_pieces.deserialize(data.get("pieces", []))
	_on_selection_changed(null)
