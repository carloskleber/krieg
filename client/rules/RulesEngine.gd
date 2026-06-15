class_name RulesEngine
extends RefCounted

## The umpire's assistant (ADR-0005, Phase 2 / M4). Composes the active Ruleset
## with the board's terrain + elevation models and answers the two *advisory*
## questions the M4 overlays draw: how far can this unit move this turn, and can
## it see that point. It enforces nothing — results are suggestions, exactly
## like an umpire's ruling that the players are free to honour or ignore.
##
## All maths happen in scenario metres (the engine is renderer-agnostic, ADR-0001
## /0005); callers convert to Godot world space at the draw boundary via Geo.
## Every query is a pure function of (state, ruleset, terrain) — the same shape
## an agent will later call (ADR-0008).

# Registry of selectable rulesets (extend as editions land; ADR-0005).
const RULESET_IDS := ["none", "strategos"]

var ruleset: Ruleset = null         # null when rules are off (sandbox)
var terrain: TerrainModel = null
var elevation: ElevationField = null

# Reach sweep tuning. Direction count trades smoothness for cost; the step is
# the marching granularity in metres.
const REACH_DIRS := 64
const REACH_STEP_M := 8.0
# Hard cap so a unit that finds an all-road corridor can't loop forever.
const REACH_MAX_FACTOR := 4.0

# LOS profile sampling.
const LOS_STEP_M := 8.0
const LOS_EPS_M := 0.4              # ground must clear the sightline by this much

func enabled() -> bool:
	return ruleset != null

# Human-readable names for play-terrain / LOS-cause tokens, shared by the HUD
# hover caption and the LOS readout so both speak the same language.
const TERRAIN_LABELS := {
	"open": "open ground", "field": "fields", "wood": "woods",
	"settlement": "village", "building": "buildings", "water": "water",
	"road": "road", "terrain": "high ground",
}

static func terrain_label(token: String) -> String:
	return TERRAIN_LABELS.get(token, token)

static func make_ruleset(rid: String) -> Ruleset:
	match rid:
		"strategos":
			return Strategos.new()
		_:
			return null

## Point the engine at a scenario and choose a ruleset by id ("none" = off).
## The board models are built regardless of the ruleset: they are pure scenario
## data and the HUD's terrain-under-cursor readout wants them even in the
## rules-off sandbox. Reach/LOS still no-op while `ruleset` is null.
func configure(scenario: Scenario, rid: String) -> void:
	ruleset = make_ruleset(rid)
	if terrain == null:
		terrain = TerrainModel.from_scenario(scenario)
	if elevation == null:
		elevation = ElevationField.from_scenario(scenario)

# --- Advisory movement reach ------------------------------------------------

## Polygon (scenario metres) a unit of `unit_type` at `origin_m` can reach in one
## turn, accounting for terrain: roads bulge it out, woods/villages pinch it in,
## water/impassable terrain stops a spoke dead. Returns empty if rules are off or
## the unit cannot move at all.
func reachable_region(unit_type: String, origin_m: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if ruleset == null or terrain == null:
		return out
	var budget := ruleset.movement_budget(unit_type)
	if budget <= 0.0:
		return out
	var max_dist := budget * REACH_MAX_FACTOR
	for i in REACH_DIRS:
		var ang := TAU * float(i) / float(REACH_DIRS)
		var dir := Vector2(cos(ang), sin(ang))
		out.append(origin_m + dir * _spoke_reach(unit_type, origin_m, dir, budget, max_dist))
	return out

# March one spoke, spending the movement budget against per-metre terrain cost,
# and return the distance reached before the budget runs out or the way is shut.
func _spoke_reach(unit_type: String, origin: Vector2, dir: Vector2, budget: float, max_dist: float) -> float:
	var spent := 0.0
	var dist := 0.0
	while dist < max_dist:
		var sample := origin + dir * (dist + REACH_STEP_M * 0.5)   # mid-step terrain
		var terr := terrain.movement_terrain_at(sample)
		var cpm := ruleset.cost_per_metre(unit_type, terr)
		if is_inf(cpm):
			break                                                  # impassable: stop here
		# Climbing costs more, descending a little less — make the reach respond
		# to the slope it crosses rather than treating the board as flat.
		cpm *= ruleset.slope_cost_factor(_grade_along(origin, dir, dist))
		var step_cost := cpm * REACH_STEP_M
		if spent + step_cost >= budget:
			# Partial final step: spend exactly the remainder.
			dist += (budget - spent) / cpm
			return dist
		spent += step_cost
		dist += REACH_STEP_M
	return dist

# Signed ground grade (rise/run) across the step starting at `dist` along a spoke.
func _grade_along(origin: Vector2, dir: Vector2, dist: float) -> float:
	if elevation == null:
		return 0.0
	var z0 := elevation.elevation_at(origin + dir * dist)
	var z1 := elevation.elevation_at(origin + dir * (dist + REACH_STEP_M))
	return (z1 - z0) / REACH_STEP_M

# --- Advisory line of sight -------------------------------------------------

## Can an observer of `unit_type` at `from_m` see `to_m`? Walks the ground
## profile between them (interpolated elevation + any wood canopy / rooflines)
## and checks nothing rises above the sightline drawn between the two eye
## heights. Returns { visible: bool, block_m: Vector2, cause: String } —
## block_m is the first obstruction and `cause` names what stopped the view
## ("terrain" for a ridge/rising ground, else the cover: wood/settlement/
## building); both are valid only when not visible.
func line_of_sight(unit_type: String, from_m: Vector2, to_m: Vector2) -> Dictionary:
	var result := {"visible": true, "block_m": to_m, "cause": ""}
	if ruleset == null or terrain == null or elevation == null:
		return result
	var total := from_m.distance_to(to_m)
	if total <= LOS_STEP_M:
		return result
	var eye := ruleset.observer_height(unit_type)
	var eye_from := elevation.elevation_at(from_m) + eye
	var eye_to := elevation.elevation_at(to_m) + eye
	var dir := (to_m - from_m) / total
	var d := LOS_STEP_M
	# Don't let the observer's/target's own cover block their own view.
	var skirt := LOS_STEP_M * 1.5
	while d < total - LOS_STEP_M:
		var p := from_m + dir * d
		var bare := elevation.elevation_at(p)
		var cover := "open"
		var ground := bare
		if d > skirt and d < total - skirt:
			cover = terrain.cover_at(p)
			ground += ruleset.los_occluder_height(cover)
		var t := d / total
		var sightline: float = lerpf(eye_from, eye_to, t)
		if ground > sightline + LOS_EPS_M:
			result.visible = false
			result.block_m = p
			# Rising ground blocks before its cover does; otherwise the canopy
			# or rooftop is the culprit.
			result.cause = "terrain" if bare > sightline + LOS_EPS_M else cover
			return result
		d += LOS_STEP_M
	return result
