class_name UnitCatalogue
extends RefCounted

## The roster of placeable pieces, styled as 19th-century wooden blocks.
## Only the three period combat arms plus command/markers (PLAN §1 non-goals:
## no naval/air/armour). Block dimensions are in METRES so pieces sit in scale
## with the board (ADR-0004 world is metres); at 1:8000 these read as graspable
## tokens without being literal footprints.

# --- Sides (factions) -------------------------------------------------------
# Muted, painted-wood tones rather than bright video-game colours.
const SIDES := {
	"blue":    {"label": "Blue",    "color": Color(0.247, 0.318, 0.471)},
	"red":     {"label": "Red",     "color": Color(0.557, 0.231, 0.212)},
	"neutral": {"label": "Neutral", "color": Color(0.451, 0.420, 0.360)},
}
const SIDE_ORDER := ["blue", "red", "neutral"]

# --- Unit types -------------------------------------------------------------
# symbol: single glyph drawn on the block (period map convention-ish).
# size: block extent in metres (width = frontage, height = depth).
const TYPES := {
	"infantry":  {"label": "Infantry",  "symbol": "I",  "size": Vector2(120, 70)},
	"cavalry":   {"label": "Cavalry",   "symbol": "C",  "size": Vector2(130, 70)},
	"artillery": {"label": "Artillery", "symbol": "A",  "size": Vector2(110, 70)},
	"hq":        {"label": "HQ",        "symbol": "H",  "size": Vector2(90, 90)},
	"marker":    {"label": "Marker",    "symbol": "•",  "size": Vector2(60, 60)},
}
const TYPE_ORDER := ["infantry", "cavalry", "artillery", "hq", "marker"]

static func type_def(type_id: String) -> Dictionary:
	return TYPES.get(type_id, TYPES["marker"])

static func side_def(side_id: String) -> Dictionary:
	return SIDES.get(side_id, SIDES["neutral"])

static func is_type(type_id: String) -> bool:
	return TYPES.has(type_id)

static func is_side(side_id: String) -> bool:
	return SIDES.has(side_id)
