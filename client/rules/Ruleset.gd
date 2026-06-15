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

# --- Slope (shared engine maths) --------------------------------------------

## Extra cost multiplier for crossing ground at `grade` (rise/run, signed:
## positive uphill, negative downhill). Open ground on the flat is 1.0. Climbing
## is dear, a gentle descent is a little quicker, and a steep descent slows again
## as troops have to brake — so reach bulges downhill and pinches uphill instead
## of being a plain circle. Provisional constants (ADR-0007), shared by every
## ruleset; override to retune. INF-safe: the engine multiplies cost_per_metre.
const UPHILL_COST := 4.0           # per unit of uphill grade
const DOWNHILL_EASE := 1.6         # gentle descent speeds a unit up
const DOWNHILL_BRAKE := 3.0        # steep descent slows it again
const DOWNHILL_EASY_GRADE := 0.18  # grade past which descent stops helping
const SLOPE_FACTOR_FLOOR := 0.4    # downhill can never be a free-fall

func slope_cost_factor(grade: float) -> float:
	if grade >= 0.0:
		return 1.0 + UPHILL_COST * grade
	var drop := -grade
	var ease := DOWNHILL_EASE * minf(drop, DOWNHILL_EASY_GRADE)
	var brake := DOWNHILL_BRAKE * maxf(0.0, drop - DOWNHILL_EASY_GRADE)
	return maxf(SLOPE_FACTOR_FLOOR, 1.0 - ease + brake)

# --- Line of sight (override the heights) -----------------------------------

## Eye height of a standing/mounted observer above the ground, in metres.
func observer_height(_unit_type: String) -> float:
	return 2.0

## How much a patch of `terrain` rises above bare ground for sighting purposes —
## a wood's canopy, a village's roofline. 0 for open/field/water. Used by the
## engine's elevation-profile LOS test.
func los_occluder_height(_terrain: String) -> float:
	return 0.0
