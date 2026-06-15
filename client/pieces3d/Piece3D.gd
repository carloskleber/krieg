class_name Piece3D
extends Node3D

## A volumetric wooden block token for the 3D board (ADR-0009) — the 3D analogue
## of Piece. Same data model and the same serialised dict (metres + facing +
## stack), so a game state saved in either view loads in the other; the ground
## height is derived from the terrain, never stored. The node origin sits on the
## terrain surface and the block rises from it.

const PIECE_LAYER := 2              # collision layer for selection raycasts
const WOOD := Color(0.682, 0.553, 0.388)
const SELECT := Color(0.949, 0.808, 0.345)
const BLOCK_H := 38.0              # block height in metres (gives it volume)
const LABEL_PIXEL_SIZE := 0.5

var id := ""
var type_id := "marker"
var side := "neutral"
var label := ""
var stack_count := 1
var facing_deg := 0.0
var selected := false

var _body: StaticBody3D
var _ring: MeshInstance3D
var _label3d: Label3D

func setup(p_id: String, p_type: String, p_side: String) -> void:
	id = p_id
	type_id = p_type if UnitCatalogue.is_type(p_type) else "marker"
	side = p_side if UnitCatalogue.is_side(p_side) else "neutral"
	_rebuild()

func footprint() -> Vector2:
	return UnitCatalogue.type_def(type_id).size

## Board position in metres (ADR-0004) — shared accessor with Piece (2D).
func metres() -> Vector2:
	return Geo3D.to_metres(global_position)

func facing_degrees() -> float:
	return facing_deg

func set_facing(deg: float) -> void:
	facing_deg = deg
	# Compass turn: +facing rotates clockwise seen from above (north = -Z).
	rotation.y = deg_to_rad(-deg)

func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	if _ring != null:
		_ring.visible = value

func set_label(text: String) -> void:
	label = text
	if _label3d != null:
		_label3d.text = text
		_label3d.visible = not text.is_empty()

func cycle_side() -> void:
	var i := UnitCatalogue.SIDE_ORDER.find(side)
	side = UnitCatalogue.SIDE_ORDER[(i + 1) % UnitCatalogue.SIDE_ORDER.size()]
	_rebuild()

func set_stack(n: int) -> void:
	stack_count = maxi(1, n)
	_rebuild()

# --- Persistence (shares Piece's schema, ADR-0004) --------------------------

func to_dict() -> Dictionary:
	var m := Geo3D.to_metres(global_position)
	return {
		"id": id, "type": type_id, "side": side, "label": label,
		"x_m": m.x, "y_m": m.y, "facing_deg": facing_deg, "stack": stack_count,
	}

func from_dict(d: Dictionary) -> void:
	setup(str(d.get("id", "")), str(d.get("type", "marker")), str(d.get("side", "neutral")))
	set_facing(float(d.get("facing_deg", 0.0)))
	set_label(str(d.get("label", "")))
	set_stack(int(d.get("stack", 1)))

# --- Visual construction -----------------------------------------------------

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_body = null
	_ring = null
	_label3d = null

	var fp := footprint()
	var side_col: Color = UnitCatalogue.side_def(side).color

	# Stack illusion: faint blocks behind/under the top one.
	for i in range(mini(stack_count - 1, 3), 0, -1):
		var off := i * 6.0
		_add_block(fp, WOOD.darkened(0.12), side_col.darkened(0.12),
			Vector3(off * 0.4, -off * 0.5, off * 0.4))

	_add_block(fp, WOOD, side_col, Vector3.ZERO)
	_add_facing_marker(fp, side_col)
	_add_symbol(fp)
	_add_label(fp)
	_add_select_ring(fp)
	_add_body(fp)
	set_facing(facing_deg)

func _add_block(fp: Vector2, wood: Color, band: Color, offset: Vector3) -> void:
	# Two stacked segments sharing one footprint: a wood lower body and a painted
	# identification cap on top. They abut (no overlap), so no coplanar faces
	# fight for the depth test as the piece moves or turns.
	var band_h := BLOCK_H * 0.32
	var wood_h := BLOCK_H - band_h
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(fp.x, wood_h, fp.y)
	body.mesh = bm
	body.position = offset + Vector3(0, wood_h * 0.5, 0)
	body.material_override = _matte(wood)
	add_child(body)
	var cap := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(fp.x, band_h, fp.y)
	cap.mesh = sm
	cap.position = offset + Vector3(0, wood_h + band_h * 0.5, 0)
	cap.material_override = _matte(band)
	add_child(cap)

func _add_facing_marker(fp: Vector2, col: Color) -> void:
	# A small wedge at the north (−Z, local front) edge marks facing.
	var marker := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(fp.x * 0.34, BLOCK_H * 0.5, fp.y * 0.28)
	marker.mesh = pm
	marker.rotation.x = -PI / 2.0          # point the prism's apex toward −Z
	marker.position = Vector3(0, BLOCK_H + 1.0, -fp.y * 0.5 - fp.y * 0.12)
	marker.material_override = _matte(col)
	add_child(marker)

func _add_symbol(fp: Vector2) -> void:
	var sym := Label3D.new()
	sym.text = UnitCatalogue.type_def(type_id).symbol
	sym.font_size = 64
	sym.pixel_size = minf(fp.x, fp.y) / 90.0
	sym.modulate = FeatureStyles.INK
	sym.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sym.rotation.x = -PI / 2.0             # lie flat on the block's top face
	sym.position = Vector3(0, BLOCK_H + 0.5, 0)
	sym.no_depth_test = false
	add_child(sym)

func _add_label(fp: Vector2) -> void:
	_label3d = Label3D.new()
	_label3d.text = label
	_label3d.visible = not label.is_empty()
	_label3d.font_size = 48
	_label3d.pixel_size = LABEL_PIXEL_SIZE
	_label3d.modulate = FeatureStyles.INK
	_label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label3d.position = Vector3(0, BLOCK_H + 28.0, 0)
	add_child(_label3d)

func _add_select_ring(fp: Vector2) -> void:
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	var r: float = maxf(fp.x, fp.y) * 0.5 + 12.0
	tm.inner_radius = r
	tm.outer_radius = r + 8.0
	_ring.mesh = tm
	_ring.position = Vector3(0, 1.5, 0)
	var mat := _matte(SELECT)
	mat.emission_enabled = true
	mat.emission = SELECT
	mat.emission_energy_multiplier = 0.6
	_ring.material_override = mat
	_ring.visible = selected
	add_child(_ring)

func _add_body(fp: Vector2) -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1 << (PIECE_LAYER - 1)
	_body.collision_mask = 0
	_body.set_meta("piece", self)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(fp.x, BLOCK_H, fp.y)
	cs.shape = box
	cs.position = Vector3(0, BLOCK_H * 0.5, 0)
	_body.add_child(cs)
	add_child(_body)

func _matte(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	m.metallic = 0.0
	return m
