class_name TerrainMesh3D
extends Node3D

## The 3D relief board (ADR-0009): a grid mesh displaced by the Heightfield and
## skinned with the *existing* 2D staff-map styling. Rather than re-draping every
## vector feature in 3D, the 2D TerrainRenderer is rendered once into a
## SubViewport and used as the mesh's albedo — so all of FeatureStyles /
## TerrainRenderer is reused unchanged; the map simply becomes the terrain skin.
##
## Vertical exaggeration is applied at the vertex stage and can be changed live
## (the cached per-vertex elevations are just re-scaled, no resampling).

const TERRAIN_LAYER := 1           # collision layer for camera/piece raycasts
const SEGMENTS_LONG := 220         # grid resolution along the longer board edge
const SKIN_MAX_TEXELS := 2048      # cap on the baked skin's longest side

var _mesh_inst: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D
var _material: StandardMaterial3D

var _cols := 0
var _rows := 0
var _size := Vector2.ZERO           # board metres
var _plan := PackedVector2Array()   # per-vertex (mx, my)
var _elev := PackedFloat32Array()   # per-vertex ground elevation (metres)
var _uv := PackedVector2Array()
var _indices := PackedInt32Array()
var _exag := 3.0

## Build the terrain. Async because the skin is baked from a SubViewport that
## needs a couple of frames to render. Call with `await`.
func build(scenario: Scenario, heightfield: Heightfield, exaggeration: float) -> void:
	_exag = exaggeration
	_size = scenario.board_size_m()
	_compute_grid(heightfield)

	_material = StandardMaterial3D.new()
	_material.albedo_texture = await _bake_skin(scenario)
	_material.roughness = 0.96
	_material.metallic = 0.0
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "TerrainSurface"
	add_child(_mesh_inst)

	_body = StaticBody3D.new()
	_body.name = "TerrainBody"
	_body.collision_layer = 1 << (TERRAIN_LAYER - 1)
	_body.collision_mask = 0
	_shape = CollisionShape3D.new()
	_body.add_child(_shape)
	add_child(_body)

	_rebuild_surface()

## Change vertical exaggeration live (re-scales heights, rebuilds the surface).
func set_exaggeration(exaggeration: float) -> void:
	if is_equal_approx(exaggeration, _exag):
		return
	_exag = exaggeration
	if _mesh_inst != null:
		_rebuild_surface()

## Board metres -> world point on the terrain surface (height included).
func surface_point(m: Vector2, heightfield: Heightfield) -> Vector3:
	return Geo3D.to_world3(m, heightfield.elevation_at(m), _exag)

# --- Grid + surface ----------------------------------------------------------

func _compute_grid(heightfield: Heightfield) -> void:
	var longer := maxf(_size.x, _size.y)
	_cols = maxi(2, int(round(SEGMENTS_LONG * _size.x / longer)))
	_rows = maxi(2, int(round(SEGMENTS_LONG * _size.y / longer)))
	_plan.clear(); _elev.clear(); _uv.clear(); _indices.clear()
	for j in range(_rows + 1):
		for i in range(_cols + 1):
			var mx := _size.x * float(i) / _cols
			var my := _size.y * float(j) / _rows
			_plan.append(Vector2(mx, my))
			_elev.append(heightfield.elevation_at(Vector2(mx, my)))
			# v flips: grid row 0 is the south edge (my = 0) -> texture bottom.
			_uv.append(Vector2(float(i) / _cols, 1.0 - float(j) / _rows))
	var stride := _cols + 1
	for j in range(_rows):
		for i in range(_cols):
			var a := j * stride + i
			var b := a + 1
			var c := a + stride
			var d := c + 1
			# Wind CCW seen from above (+Y) so faces point up under back-culling.
			_indices.append(a); _indices.append(c); _indices.append(b)
			_indices.append(b); _indices.append(c); _indices.append(d)

func _rebuild_surface() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in _plan.size():
		st.set_uv(_uv[k])
		st.add_vertex(Geo3D.to_world3(_plan[k], _elev[k], _exag))
	for idx in _indices:
		st.add_index(idx)
	st.generate_normals()
	var mesh := st.commit()
	_mesh_inst.mesh = mesh
	_mesh_inst.material_override = _material
	_shape.shape = mesh.create_trimesh_shape()

# --- Skin bake ---------------------------------------------------------------

# Render the 2D TerrainRenderer into an offscreen viewport and capture it as a
# texture aligned to the board rect, so the relief mesh wears the staff map.
func _bake_skin(scenario: Scenario) -> ImageTexture:
	var scale := minf(float(SKIN_MAX_TEXELS) / maxf(_size.x, _size.y), 1.0)
	var vp := SubViewport.new()
	vp.size = Vector2i(maxi(1, ceili(_size.x * scale)), maxi(1, ceili(_size.y * scale)))
	vp.transparent_bg = false
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	# Frame the board's world rect [0,-h]..[w,0] exactly onto the viewport.
	var rect := Rect2(0, -_size.y, _size.x, _size.y)
	var cam := Camera2D.new()
	cam.position = rect.get_center()
	cam.zoom = Vector2(vp.size.x / rect.size.x, vp.size.y / rect.size.y)
	vp.add_child(cam)
	cam.make_current()

	var renderer := TerrainRenderer.new()
	vp.add_child(renderer)
	renderer.build(scenario)

	# Let the SubViewport render, then grab a standalone image.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return ImageTexture.create_from_image(img)
