class_name FeatureStyles
extends RefCounted

## Period staff-map palette and per-category draw parameters.
##
## Stylisation lives entirely in the client (ADR-0004: the package only tags a
## category; "no rendering here — just classification"). The look targets a 19th
## century printed staff map: aged paper, sepia ink, muted washes.

# --- Paper / base -----------------------------------------------------------
const PAPER := Color(0.886, 0.835, 0.737)          # parchment (matches clear color)
const INK := Color(0.231, 0.184, 0.122)            # sepia ink for outlines/labels
const INK_FAINT := Color(0.231, 0.184, 0.122, 0.55)

# --- Category fills ---------------------------------------------------------
const WATER_FILL := Color(0.498, 0.659, 0.722, 0.85)
const WATER_LINE := Color(0.290, 0.439, 0.510)
const WOOD_FILL := Color(0.514, 0.596, 0.388, 0.55)
const WOOD_LINE := Color(0.353, 0.451, 0.255)
const FIELD_FILL := Color(0.847, 0.804, 0.643, 0.45)
const SETTLEMENT_FILL := Color(0.745, 0.514, 0.408, 0.55)
const SETTLEMENT_LINE := Color(0.486, 0.302, 0.224)
const BUILDING_FILL := Color(0.545, 0.353, 0.235)
const STRONGPOINT_LINE := Color(0.620, 0.094, 0.094)   # red ring for strongpoints

# --- Relief (contours) ------------------------------------------------------
const CONTOUR := Color(0.561, 0.420, 0.282, 0.85)
const CONTOUR_INDEX := Color(0.451, 0.318, 0.196)      # every Nth (index) contour

# --- Roads (period classes, ADR-0006) ---------------------------------------
# Width in METRES (drawn in world space, so it scales with zoom like real ground).
const ROAD_STYLES := {
	"chaussee":  {"color": Color(0.420, 0.286, 0.149), "width": 6.0, "casing": true},
	"highroad":  {"color": Color(0.420, 0.286, 0.149), "width": 6.0, "casing": true},
	"road":      {"color": Color(0.471, 0.353, 0.220), "width": 4.0, "casing": false},
	"track":     {"color": Color(0.471, 0.353, 0.220), "width": 2.5, "casing": false, "dashed": true},
	"path":      {"color": Color(0.471, 0.353, 0.220), "width": 1.5, "casing": false, "dashed": true},
}
const ROAD_DEFAULT := {"color": Color(0.471, 0.353, 0.220), "width": 3.0, "casing": false}
const ROAD_CASING := Color(0.290, 0.196, 0.102)        # darker outline under main roads
const BRIDGE := Color(0.184, 0.137, 0.090)

static func road_style(road_class: String) -> Dictionary:
	return ROAD_STYLES.get(road_class, ROAD_DEFAULT)

## Interpolate a contour tint by elevation so relief reads at a glance: lower
## ground cooler/greener, higher ground warmer/browner.
static func contour_color(elevation: float, lo: float, hi: float, is_index: bool) -> Color:
	var base := CONTOUR_INDEX if is_index else CONTOUR
	if hi <= lo:
		return base
	var t := clampf((elevation - lo) / (hi - lo), 0.0, 1.0)
	var low_tint := Color(0.451, 0.490, 0.353)   # greenish for valleys
	var high_tint := Color(0.561, 0.380, 0.231)  # brown for heights
	return low_tint.lerp(high_tint, t).lerp(base, 0.35 if not is_index else 0.55)
