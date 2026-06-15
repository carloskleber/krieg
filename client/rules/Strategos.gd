class_name Strategos
extends Ruleset

## The first concrete ruleset: *Strategos* (Totten, 1880), the edition ADR-0005
## resolves to target first. Everything play-tunable lives here as DATA — a
## small table, not code (ADR-0007) — so balancing is a config edit and other
## editions are just other Ruleset subclasses.
##
## The numbers are period-plausible STARTING GUESSES to be tuned by playtesting
## (ADR-0007 explicitly flags the rates as provisional). Turn = ~2 min, so e.g.
## infantry "open" 150 m/turn ≈ 4.5 km/h marching; cavalry "open" 300 m/turn ≈
## 9 km/h at the trot; artillery is road-bound and crawls off it.

const TURN_SECONDS := 120.0

## metres per turn, keyed [unit_type][terrain]. 0 = impassable for that arm.
## Markers/HQ borrow sensible defaults; only the three combat arms are tuned.
const RATES := {
	"infantry":  {"road": 220, "open": 150, "field": 135, "wood": 70, "settlement": 90, "building": 45, "water": 0},
	"cavalry":   {"road": 460, "open": 300, "field": 255, "wood": 80, "settlement": 110, "building": 0, "water": 0},
	"artillery": {"road": 200, "open": 100, "field": 80, "wood": 35, "settlement": 55, "building": 0, "water": 0},
	"hq":        {"road": 320, "open": 220, "field": 190, "wood": 90, "settlement": 130, "building": 70, "water": 0},
	"marker":    {"road": 200, "open": 150, "field": 135, "wood": 70, "settlement": 90, "building": 45, "water": 0},
}

## Standing observer + arm bonus (cavalry sit higher; HQ assumed on good ground).
const OBSERVER_HEIGHT := {
	"infantry": 1.8, "cavalry": 2.6, "artillery": 1.8, "hq": 2.2, "marker": 1.8,
}

## How far each cover type rises above bare ground for sighting (canopy/roofs).
const OCCLUDER_HEIGHT := {
	"wood": 14.0, "settlement": 9.0, "building": 11.0,
	"open": 0.0, "field": 0.0, "road": 0.0, "water": 0.0,
}

func id() -> String:
	return "strategos"

func display_name() -> String:
	return "Strategos (1880)"

func edition() -> String:
	return "Totten, 1880"

func turn_seconds() -> float:
	return TURN_SECONDS

func movement_rate(unit_type: String, terrain: String) -> float:
	var row: Dictionary = RATES.get(unit_type, RATES["marker"])
	return float(row.get(terrain, row.get("open", 0.0)))

func observer_height(unit_type: String) -> float:
	return float(OBSERVER_HEIGHT.get(unit_type, 1.8))

func los_occluder_height(terrain: String) -> float:
	return float(OCCLUDER_HEIGHT.get(terrain, 0.0))
