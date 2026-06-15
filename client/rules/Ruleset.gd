class_name Ruleset
extends RefCounted

## The pluggable rules interface (ADR-0005). A ruleset is plain data + pure
## functions over game-state values; it never touches the Godot renderer, so it
## is testable in isolation and swappable (Strategos, Reisswitz, house variants).
##
## Phase 2 / M4 surfaces only the *advisory* half of this interface — movement
## rates and line-of-sight parameters, consumed as overlays that suggest but
## never prevent a move (ADR-0005: "advisory before enforced"). Combat
## resolution (M5) will extend this base with seeded-RNG methods; the signatures
## here are deliberately the queries an AI agent will also call (ADR-0008).
##
## Subclasses override the DATA accessors below; the geometry-free helpers
## (cost-per-metre, occluder height lookups) stay here so every ruleset shares
## the same engine maths.

## Distinct terrain categories the movement/LOS tables are keyed by. These are a
## play-level grouping of the scenario's feature categories (ADR-0004/0006):
## "open" is the implicit background (no covering polygon); "road" is proximity
## to a road line, which overrides whatever polygon is underneath.
const TERRAINS := ["road", "open", "field", "wood", "settlement", "building", "water"]

# --- Identity (override) ----------------------------------------------------

func id() -> String:
	return "none"

func display_name() -> String:
	return "No rules"

func edition() -> String:
	return ""

# --- Time & movement (override the tables) ----------------------------------

## Reference turn length in seconds (the original "move" cadence, ADR-0007).
func turn_seconds() -> float:
	return 120.0

## Ground a unit covers per turn on a given terrain, in metres. 0 means
## impassable. Subclasses return this from a `unit_type × terrain` table.
func movement_rate(_unit_type: String, _terrain: String) -> float:
	return 0.0

## The per-turn movement budget: by convention the unit's rate on OPEN ground.
## The engine spends this budget marching through mixed terrain.
func movement_budget(unit_type: String) -> float:
	return movement_rate(unit_type, "open")

## Cost (in budget-metres) of crossing one metre of `terrain`, relative to open
## ground: open = 1.0, faster terrain < 1.0, slower > 1.0, impassable = INF.
## Pure function of the rate table — shared by every ruleset.
func cost_per_metre(unit_type: String, terrain: String) -> float:
	var rate := movement_rate(unit_type, terrain)
	if rate <= 0.0:
		return INF
	var budget := movement_budget(unit_type)
	if budget <= 0.0:
		return INF
	return budget / rate

# --- Line of sight (override the heights) -----------------------------------

## Eye height of a standing/mounted observer above the ground, in metres.
func observer_height(_unit_type: String) -> float:
	return 2.0

## How much a patch of `terrain` rises above bare ground for sighting purposes —
## a wood's canopy, a village's roofline. 0 for open/field/water. Used by the
## engine's elevation-profile LOS test.
func los_occluder_height(_terrain: String) -> float:
	return 0.0
