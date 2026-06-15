class_name View3D
extends Node3D

## Root of the optional 3D board (ADR-0009): the relief terrain, a sun light tuned
## to the staff-map hillshade, an environment for ambient fill, an orbit camera,
## and the 3D piece layer. Assembled once from a scenario; the 2D board is left
## untouched and the ViewManager toggles which is shown.

const DEFAULT_EXAGGERATION := 3.0

var scenario: Scenario
var heightfield: Heightfield
var terrain: TerrainMesh3D
var volumes: FeatureVolumes3D
var camera: CameraController3D
var piece_layer: Piece3DLayer

var _light: DirectionalLight3D
var _exag := DEFAULT_EXAGGERATION

## Assemble the 3D board. Async: the terrain skin bakes from a SubViewport.
func build(s: Scenario, exaggeration := DEFAULT_EXAGGERATION) -> void:
	scenario = s
	_exag = exaggeration
	heightfield = Heightfield.from_scenario(s)

	_build_environment()
	_build_light()

	terrain = TerrainMesh3D.new()
	terrain.name = "Terrain"
	add_child(terrain)
	await terrain.build(s, heightfield, _exag)

	volumes = FeatureVolumes3D.new()
	volumes.name = "Volumes"
	add_child(volumes)
	volumes.build(s, heightfield, _exag)

	camera = CameraController3D.new()
	camera.name = "Camera3D"
	add_child(camera)

	piece_layer = Piece3DLayer.new()
	piece_layer.name = "Pieces3D"
	add_child(piece_layer)
	piece_layer.configure(camera, terrain, heightfield)

	frame()

## Frame the whole board, focusing on the mid-elevation centre.
func frame() -> void:
	if camera == null:
		return
	var size := scenario.board_size_m()
	var er := scenario.elevation_range_m()
	var mid := (er.x + er.y) * 0.5 * _exag
	camera.frame_board(size, mid)

func exaggeration() -> float:
	return _exag

## Live vertical-exaggeration change: re-scale terrain and re-ground every piece.
func set_exaggeration(value: float) -> void:
	if is_equal_approx(value, _exag) or terrain == null:
		return
	var ratio := value / _exag if _exag > 0.0 else 1.0
	_exag = value
	terrain.set_exaggeration(value)
	if volumes != null:
		volumes.set_exaggeration(value)
	if camera != null:
		# Heights scale linearly with exaggeration, so the orbit pivot (parked at
		# the old exaggerated mid-height) must rescale too — otherwise it floats
		# above the board as relief flattens, dragging the centre of rotation up.
		camera.rescale_height(ratio)
	if piece_layer != null:
		# Re-seat pieces on the new surface (positions in metres are unchanged).
		piece_layer.deserialize(piece_layer.serialize())

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.886, 0.835, 0.737)   # parchment, matches 2D
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.82, 0.76)
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)

func _build_light() -> void:
	_light = DirectionalLight3D.new()
	_light.name = "Sun"
	_light.light_energy = 1.05
	_light.shadow_enabled = true
	_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(_light)
	# Light from the NW (azimuth 315°, ~45° altitude) to match the hillshade, so
	# relief shades the same way it reads on the 2D staff map.
	_light.look_at_from_position(Vector3.ZERO, Vector3(1.0, -1.1, 1.0), Vector3.UP)
