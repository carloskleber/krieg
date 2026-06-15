class_name FeatureVolumes3D
extends Node3D

## Raised 3D volumes for buildings and woods on the relief board (ADR-0009).
##
## The terrain mesh (TerrainMesh3D) only wears the flat staff-map skin, so towns
## and forests read as paint. This adds actual mass: building footprints extrude
## into flat-roofed blocks standing on the ground, and wood polygons into a
## terrain-following canopy. Like the relief, heights live in the *exaggerated*
## vertical space, so they stay proportional to the terrain and a live
## exaggeration change is just a rebuild at the new scale.

const BUILDING_HEIGHT_M := 9.0
const STRONGPOINT_HEIGHT_M := 16.0   # churches / fortified points stand taller
const WOOD_HEIGHT_M := 12.0

var _scenario: Scenario
var _heightfield: Heightfield
var _exag := 3.0

var _building_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D

func build(scenario: Scenario, heightfield: Heightfield, exaggeration: float) -> void:
	_scenario = scenario
	_heightfield = heightfield
	_exag = exaggeration
	# Walls and caps carry explicit normals; culling is disabled so a footprint's
	# winding never hides a face (the interior faces sit inside solid mass anyway).
	_building_mat = _make_material(FeatureStyles.BUILDING_FILL)
	_wood_mat = _make_material(Color(0.376, 0.475, 0.282))
	_rebuild()

## Live vertical-exaggeration change: re-extrude at the new scale.
func set_exaggeration(exaggeration: float) -> void:
	if is_equal_approx(exaggeration, _exag):
		return
	_exag = exaggeration
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	if _scenario == null:
		return
	var buildings := SurfaceTool.new()
	buildings.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_b := false
	var woods := SurfaceTool.new()
	woods.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_w := false
	for f in _scenario.features:
		match f.category:
			"building":
				var role := str(f.props.get("building_role", ""))
				var h := STRONGPOINT_HEIGHT_M if role == "strongpoint" else BUILDING_HEIGHT_M
				for ring in f.parts:
					has_b = _extrude(buildings, ring, h, true) or has_b
			"wood":
				for ring in f.parts:
					has_w = _extrude(woods, ring, WOOD_HEIGHT_M, false) or has_w
	if has_b:
		_commit(buildings, _building_mat, "Buildings")
	if has_w:
		_commit(woods, _wood_mat, "Woods")

func _commit(st: SurfaceTool, mat: StandardMaterial3D, mesh_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

# Extrude one footprint/polygon ring into a prism standing on the terrain and
# append it to `st`. `flat_top` gives buildings a level roof (so walls vary with
# the ground); otherwise the top rides the terrain at a constant height, as a
# wood canopy does. Returns false if the ring is too small to form a solid.
func _extrude(st: SurfaceTool, ring: PackedVector2Array, height_m: float, flat_top: bool) -> bool:
	var plan := _open(ring)
	var n := plan.size()
	if n < 3:
		return false
	var ground := PackedFloat32Array()
	ground.resize(n)
	var top := PackedFloat32Array()
	top.resize(n)
	var centroid := Vector2.ZERO
	var max_g := -INF
	for i in n:
		var g := _heightfield.elevation_at(plan[i])
		ground[i] = g
		max_g = maxf(max_g, g)
		centroid += plan[i]
	centroid /= n
	for i in n:
		top[i] = (max_g + height_m) if flat_top else (ground[i] + height_m)

	# Walls: one outward-facing quad per footprint edge.
	for i in n:
		var j := (i + 1) % n
		var a := plan[i]
		var b := plan[j]
		var nrm := _outward_normal(a, b, centroid)
		var a0 := Geo3D.to_world3(a, ground[i], _exag)
		var b0 := Geo3D.to_world3(b, ground[j], _exag)
		var a1 := Geo3D.to_world3(a, top[i], _exag)
		var b1 := Geo3D.to_world3(b, top[j], _exag)
		_tri(st, nrm, a0, b0, b1)
		_tri(st, nrm, a0, b1, a1)

	# Roof / canopy cap, triangulated in plan and lifted to the top elevations.
	var idx := Geometry2D.triangulate_polygon(plan)
	for k in range(0, idx.size(), 3):
		_tri(st, Vector3.UP,
			Geo3D.to_world3(plan[idx[k]], top[idx[k]], _exag),
			Geo3D.to_world3(plan[idx[k + 1]], top[idx[k + 1]], _exag),
			Geo3D.to_world3(plan[idx[k + 2]], top[idx[k + 2]], _exag))
	return true

func _tri(st: SurfaceTool, nrm: Vector3, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	st.set_normal(nrm)
	st.add_vertex(p0)
	st.set_normal(nrm)
	st.add_vertex(p1)
	st.set_normal(nrm)
	st.add_vertex(p2)

# Horizontal normal for a wall edge, flipped to point away from the footprint
# interior. Works in world XZ, where scenario north (+y) maps to -z.
func _outward_normal(a: Vector2, b: Vector2, centroid: Vector2) -> Vector3:
	var aw := Vector2(a.x, -a.y)
	var bw := Vector2(b.x, -b.y)
	var cw := Vector2(centroid.x, -centroid.y)
	var edge := bw - aw
	var nrm := Vector2(-edge.y, edge.x)
	var mid := (aw + bw) * 0.5
	if nrm.dot(mid - cw) < 0.0:
		nrm = -nrm
	nrm = nrm.normalized()
	return Vector3(nrm.x, 0.0, nrm.y)

func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# Drop a ring's repeated closing vertex (triangulation/edges want it open).
func _open(ring: PackedVector2Array) -> PackedVector2Array:
	if ring.size() >= 2 and ring[0] == ring[ring.size() - 1]:
		return ring.slice(0, ring.size() - 1)
	return ring
