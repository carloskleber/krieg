class_name Geo
extends RefCounted

## Coordinate helpers between the scenario package (ADR-0004) and Godot's 2D world.
##
## The package stores geometry in local metres with the origin at the bbox's
## south-west corner and +y pointing NORTH (UTM northing grows northward).
## Godot 2D has +y pointing DOWN. To keep the board north-up *and* keep piece
## labels upright, we never flip a node's scale; instead every metre coordinate
## is converted to a world coordinate by negating y. 1 world unit = 1 metre.

static func to_world(metres: Vector2) -> Vector2:
	return Vector2(metres.x, -metres.y)

static func to_metres(world: Vector2) -> Vector2:
	return Vector2(world.x, -world.y)

## Distance in metres between two world points (1:1, so just the length).
static func world_distance_m(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)
