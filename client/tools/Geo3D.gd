class_name Geo3D
extends RefCounted

## Coordinate helpers for the optional 3D board view (ADR-0009), the 3D analogue
## of Geo (ADR-0004).
##
## The scenario package stores geometry in local metres with +x EAST, +y NORTH,
## and elevation up. Godot 3D is y-up. We map NORTH to −Z so that a default
## bird's-eye camera placed to the south looks north and the board reads
## north-up, consistent with the 2D board (Geo negates y for the same reason).
## Elevation is multiplied by a vertical exaggeration so relief is legible at the
## game scale (~80 m over ~3.6 km is otherwise almost flat).
##
##   metres (x, y north) + elev  ->  Vector3(x, elev * exaggeration, -y)
##
## 1 horizontal world unit = 1 metre. Exaggeration only scales the vertical axis,
## so plan-distances and piece footprints stay true.

static func to_world3(metres: Vector2, elev: float, exaggeration: float) -> Vector3:
	return Vector3(metres.x, elev * exaggeration, -metres.y)

## World (x, z) back to scenario metres (drops height; y north = -world.z).
static func to_metres(world: Vector3) -> Vector2:
	return Vector2(world.x, -world.z)

## Horizontal (plan) metres between two world points, ignoring height.
static func plan_distance_m(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
